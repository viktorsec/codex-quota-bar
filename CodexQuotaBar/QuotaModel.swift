import AppKit
import Observation

struct QuotaWindow: Identifiable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetsAt: Date?

    var remainingPercent: Int { Int((100 - usedPercent).rounded(.down)) }

    static func parse(_ response: [String: Any]) -> [QuotaWindow] {
        // Newer servers may return multiple metered buckets. Avoid duplicating
        // the backward-compatible single bucket when both views are present.
        let buckets: [(String, [String: Any])]
        if let multiple = response["rateLimitsByLimitId"] as? [String: [String: Any]], !multiple.isEmpty {
            buckets = multiple.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        } else if let single = response["rateLimits"] as? [String: Any] {
            buckets = [(single["limitId"] as? String ?? "codex", single)]
        } else {
            return []
        }
        return buckets.flatMap { bucketID, bucket in
            ["primary", "secondary"].compactMap { key in
                guard let window = bucket[key] as? [String: Any],
                      let used = window["usedPercent"] as? Double,
                      used.isFinite, (0...100).contains(used) else { return nil }
                let minutes = window["windowDurationMins"] as? Int
                let duration: String
                switch minutes {
                case 10_080: duration = "Weekly"
                case let value? where value > 0 && value % 60 == 0: duration = "\(value / 60)-hour"
                case let value? where value > 0: duration = "\(value)-minute"
                default: duration = key == "primary" ? "Primary" : "Secondary"
                }
                let prefix = buckets.count > 1 ? "\(bucket["limitName"] as? String ?? bucketID) · " : ""
                let reset = (window["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
                return QuotaWindow(id: "\(bucketID).\(key)", title: prefix + duration, usedPercent: used, resetsAt: reset)
            }
        }
    }
}

@Observable
@MainActor
final class QuotaModel {
    private(set) var isConnecting = false
    private(set) var isConnected = false
    private(set) var isSignedIn = false
    private(set) var isRefreshing = false
    private(set) var isSigningIn = false
    private(set) var email: String?
    private(set) var windows: [QuotaWindow] = []
    private(set) var updatedAt: Date?
    private(set) var errorMessage: String?

    @ObservationIgnored private let client = CodexClient()
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var loginTimeout: Task<Void, Never>?
    @ObservationIgnored private var loginAttempt: UUID?
    @ObservationIgnored private var loginID: String?
    @ObservationIgnored private var loginURL: URL?

    var menuBarTitle: String {
        guard isConnected else { return "Codex" }
        if let window = windows.first { return "\(window.remainingPercent)%" }
        return "Codex"
    }

    init() {
        client.onNotification = { [weak self] method, params in
            self?.receive(method, params: params)
        }
        client.onDisconnect = { [weak self] in
            guard let self else { return }
            self.polling?.cancel()
            self.isConnected = false
            self.isSigningIn = false
            self.loginTimeout?.cancel()
            self.loginID = nil
            self.loginURL = nil
            self.errorMessage = "The Codex helper stopped. Choose Reconnect to try again."
        }
    }

    func connect() {
        guard !isConnecting else { return }
        operation?.cancel()
        polling?.cancel()
        isConnecting = true
        errorMessage = nil
        operation = Task {
            defer { isConnecting = false }
            do {
                await client.stop()
                try await client.start()
                isConnected = true
                try await readAccount()
                if isSignedIn { try await readQuota() }
                startPolling()
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
                isConnected = client.isConnected
            }
        }
    }

    func signIn() {
        guard isConnected, !isConnecting, !isSignedIn, !isSigningIn, !isRefreshing else { return }
        let attempt = UUID()
        loginAttempt = attempt
        isSigningIn = true
        errorMessage = nil
        operation = Task {
            do {
                let response = try await client.request("account/login/start", params: ["type": "chatgpt"])
                guard loginAttempt == attempt else { return }
                // Keep the ID even if URL validation fails, so the helper's
                // callback listener can still be cancelled.
                guard let id = response["loginId"] as? String else {
                    throw CodexClient.ClientError.invalidResponse
                }
                loginID = id
                guard let address = response["authUrl"] as? String,
                      let url = URL(string: address), url.scheme == "https",
                      let host = url.host,
                      host == "auth.openai.com" || host == "chatgpt.com" || host == "auth0.openai.com" else {
                    throw CodexClient.ClientError.invalidResponse
                }
                loginURL = url
                guard NSWorkspace.shared.open(url) else {
                    throw NSError(domain: "CodexQuotaBar", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Could not open your browser. Cancel and try signing in again."
                    ])
                }
                loginTimeout = Task {
                    do { try await Task.sleep(for: .seconds(300)) } catch { return }
                    self.cancelSignIn()
                }
            } catch {
                // A cancelled attempt must not clear a newer attempt's state.
                guard loginAttempt == attempt else { return }
                let id = loginID
                clearLogin()
                errorMessage = error.localizedDescription
                if let id { _ = try? await client.request("account/login/cancel", params: ["loginId": id]) }
            }
        }
    }

    func reopenSignIn() {
        if let loginURL { NSWorkspace.shared.open(loginURL) }
    }

    func cancelSignIn() {
        let id = loginID
        clearLogin()
        operation?.cancel()
        // If login/start hasn't returned its ID yet, restarting the helper
        // also closes the callback listener for that pending login attempt.
        guard let id else {
            connect()
            return
        }
        operation = Task {
            _ = try? await client.request("account/login/cancel", params: ["loginId": id])
        }
    }

    func refresh() {
        guard isConnected, isSignedIn, !isRefreshing, !isSigningIn else { return }
        isRefreshing = true
        errorMessage = nil
        operation = Task {
            defer { isRefreshing = false }
            do {
                try await readAccount()
                if isSignedIn { try await readQuota() }
            } catch is CancellationError {
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func signOut() {
        guard isConnected, !isRefreshing, !isSigningIn else { return }
        isRefreshing = true
        errorMessage = nil
        operation = Task {
            defer { isRefreshing = false }
            do {
                _ = try await client.request("account/logout")
                clearAccount()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func readAccount() async throws {
        let result = try await client.request("account/read", params: ["refreshToken": false])
        try Task.checkCancellation()
        guard let account = result["account"] as? [String: Any], account["type"] as? String == "chatgpt" else {
            clearAccount()
            return
        }
        isSignedIn = true
        email = account["email"] as? String
    }

    private func readQuota() async throws {
        let result = try await client.request("account/rateLimits/read")
        try Task.checkCancellation()
        windows = QuotaWindow.parse(result)
        updatedAt = .now
    }

    private func startPolling() {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                self?.refresh()
            }
        }
    }

    private func receive(_ method: String, params: [String: Any]) {
        switch method {
        case "account/login/completed":
            guard isSigningIn, let id = loginID, params["loginId"] as? String == id else { return }
            clearLogin()
            if params["success"] as? Bool == true {
                // Read account before refresh(): the signed-in flag is still false.
                isRefreshing = true
                operation = Task {
                    defer { isRefreshing = false }
                    do {
                        try await readAccount()
                        if isSignedIn { try await readQuota() }
                    } catch is CancellationError {
                    } catch { errorMessage = error.localizedDescription }
                }
            } else {
                errorMessage = "Sign-in did not complete. Please try again."
            }
        case "account/rateLimits/updated":
            guard isSignedIn else { return }
            windows = QuotaWindow.parse(params)
            updatedAt = .now
        case "account/updated":
            if params["authMode"] is NSNull { clearAccount() }
        default: break
        }
    }

    private func clearAccount() {
        isSignedIn = false
        email = nil
        windows = []
        updatedAt = nil
    }

    private func clearLogin() {
        loginTimeout?.cancel()
        loginTimeout = nil
        loginAttempt = nil
        loginID = nil
        loginURL = nil
        isSigningIn = false
    }

    func shutdown() async {
        operation?.cancel()
        polling?.cancel()
        clearLogin()
        await client.stop()
    }
}
