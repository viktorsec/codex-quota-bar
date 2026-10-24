import AppKit
import Observation

@Observable
@MainActor
final class QuotaModel {
    enum ConnectionState { case disconnected, connecting, connected }
    enum AuthenticationState {
        case signedOut
        case signingIn(LoginAttempt)
        case signedIn(email: String?)
    }
    struct LoginAttempt {
        let id: UUID
        var serverID: String?
        var url: URL?
    }

    private(set) var connection: ConnectionState = .disconnected
    private(set) var authentication: AuthenticationState = .signedOut
    private(set) var windows: [QuotaWindow] = []
    private(set) var resetCredits: ResetCredits?
    private(set) var updatedAt: Date?
    private(set) var errorMessage: String?
    // Stable image identity avoids repeatedly invalidating MenuBarExtra layout.
    private(set) var weeklyMenuBarImage = QuotaBadge.image(window: nil, period: .weekly, now: .now)
    private(set) var fiveHourMenuBarImage = QuotaBadge.image(window: nil, period: .fiveHour, now: .now)
    private var accountOperationID: UUID?

    @ObservationIgnored private let session = AuthenticationSession()
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var loginTask: Task<Void, Never>?
    @ObservationIgnored private var accountTask: Task<Void, Never>?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var loginTimeout: Task<Void, Never>?

    var isConnecting: Bool { connection == .connecting }
    var isConnected: Bool { connection == .connected }
    var isRefreshing: Bool { accountOperationID != nil }
    var isSignedIn: Bool {
        if case .signedIn = authentication { return true }
        return false
    }
    var isSigningIn: Bool { pendingLogin != nil }
    var email: String? {
        if case .signedIn(let email) = authentication { return email }
        return nil
    }
    private var pendingLogin: LoginAttempt? {
        if case .signingIn(let attempt) = authentication { return attempt }
        return nil
    }
    var weeklyWindow: QuotaWindow? {
        quotaWindow(durationMinutes: 10_080)
    }
    var fiveHourWindow: QuotaWindow? {
        quotaWindow(durationMinutes: 300)
    }
    private func quotaWindow(durationMinutes: Int) -> QuotaWindow? {
        guard isConnected, isSignedIn else { return nil }
        let matching = windows.filter { $0.windowDurationMins == durationMinutes }
        return matching.first { $0.id.hasPrefix("codex.") } ?? matching.first
    }

    init() {
        session.onNotification = { [weak self] method, params in
            self?.receive(method, params: params)
        }
        session.onDisconnect = { [weak self] in self?.disconnected() }
    }

    func connect() {
        guard !isConnecting else { return }
        cancelPendingWork()
        clearLogin()
        clearAccount()
        connection = .connecting
        errorMessage = nil
        connectionTask = Task {
            do {
                await session.stop()
                try await session.start()
                try Task.checkCancellation()
                errorMessage = session.credentialNotice
                try await readAccountAndQuota()
                try Task.checkCancellation()
                connection = .connected
                updateMenuBarImages()
                startPolling()
            } catch is CancellationError {
                if connection == .connecting { connection = .disconnected }
            } catch {
                guard !Task.isCancelled else { return }
                connection = session.isConnected ? .connected : .disconnected
                errorMessage = error.localizedDescription
            }
        }
    }

    func signIn() {
        guard isConnected, !isSignedIn, !isSigningIn, !isRefreshing else { return }
        let attemptID = UUID()
        authentication = .signingIn(LoginAttempt(id: attemptID))
        errorMessage = nil
        loginTask = Task {
            do {
                let response = try await session.request("account/login/start", params: ["type": "chatgpt"])
                guard var attempt = pendingLogin, attempt.id == attemptID else { return }
                // Retain the server ID before validating the URL so a failed
                // browser launch can still cancel the callback listener.
                guard let id = response["loginId"] as? String else {
                    throw CodexClient.ClientError.invalidResponse
                }
                attempt.serverID = id
                authentication = .signingIn(attempt)
                guard let address = response["authUrl"] as? String,
                      let url = URL(string: address), url.scheme == "https",
                      let host = url.host,
                      host == "auth.openai.com" || host == "chatgpt.com" || host == "auth0.openai.com" else {
                    throw CodexClient.ClientError.invalidResponse
                }
                attempt.url = url
                authentication = .signingIn(attempt)
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
                guard let attempt = pendingLogin, attempt.id == attemptID else { return }
                clearLogin()
                errorMessage = error.localizedDescription
                if let id = attempt.serverID {
                    _ = try? await session.request("account/login/cancel", params: ["loginId": id])
                }
            }
        }
    }

    func reopenSignIn() {
        if let url = pendingLogin?.url { NSWorkspace.shared.open(url) }
    }

    func cancelSignIn() {
        guard let attempt = pendingLogin else { return }
        clearLogin()
        loginTask?.cancel()
        // Until login/start returns its ID, stopping the helper is the only way
        // to guarantee that its pending callback listener has been cancelled.
        guard let id = attempt.serverID else {
            connect()
            return
        }
        loginTask = Task {
            _ = try? await session.request("account/login/cancel", params: ["loginId": id])
        }
    }

    func refresh() {
        guard isConnected, isSignedIn, !isSigningIn else { return }
        performAccountOperation { try await self.readAccountAndQuota() }
    }

    func signOut() {
        guard isConnected, !isSigningIn else { return }
        performAccountOperation {
            _ = try await self.session.request("account/logout")
            try Task.checkCancellation()
            self.clearAccount()
        }
    }

    private func performAccountOperation(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isRefreshing else { return }
        let id = UUID()
        accountOperationID = id
        errorMessage = nil
        accountTask = Task {
            defer {
                // A cancelled task must not clear a newer operation's state.
                if accountOperationID == id { accountOperationID = nil }
            }
            do { try await action() }
            catch is CancellationError {
            } catch {
                if accountOperationID == id { errorMessage = error.localizedDescription }
            }
        }
    }

    private func readAccountAndQuota() async throws {
        let result = try await session.request("account/read", params: ["refreshToken": false])
        try Task.checkCancellation()
        guard let account = result["account"] as? [String: Any], account["type"] as? String == "chatgpt" else {
            clearAccount()
            return
        }
        authentication = .signedIn(email: account["email"] as? String)
        let quota = try await session.request("account/rateLimits/read")
        try Task.checkCancellation()
        windows = QuotaWindow.parse(quota)
        resetCredits = ResetCredits.parse(quota)
        updatedAt = .now
        updateMenuBarImages()
    }

    private func startPolling() {
        polling?.cancel()
        polling = Task { [weak self] in
            var minutes = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self else { return }
                self.updateMenuBarImages()
                minutes += 1
                if minutes == 5 {
                    minutes = 0
                    self.refresh()
                }
            }
        }
    }

    private func receive(_ method: String, params: [String: Any]) {
        switch method {
        case "account/login/completed":
            guard let attempt = pendingLogin, params["loginId"] as? String == attempt.serverID else { return }
            clearLogin()
            if params["success"] as? Bool == true {
                performAccountOperation { try await self.readAccountAndQuota() }
            } else {
                errorMessage = "Sign-in did not complete. Please try again."
            }
        case "account/rateLimits/updated":
            guard isSignedIn else { return }
            windows = QuotaWindow.parse(params)
            // Some notifications update only the quota windows. Keep the last
            // reset summary unless a replacement (including null) is supplied.
            if params.keys.contains("rateLimitResetCredits") {
                resetCredits = ResetCredits.parse(params)
            }
            updatedAt = .now
            updateMenuBarImages()
        case "account/updated":
            if params["authMode"] is NSNull, !isSigningIn { clearAccount() }
        default: break
        }
    }

    private func disconnected() {
        cancelPendingWork()
        clearLogin()
        connection = .disconnected
        clearAccount()
        errorMessage = "The Codex helper stopped. Choose Reconnect to try again."
    }

    private func clearAccount() {
        authentication = .signedOut
        windows = []
        resetCredits = nil
        updatedAt = nil
        updateMenuBarImages()
    }

    private func updateMenuBarImages() {
        let now = Date.now
        weeklyMenuBarImage = QuotaBadge.image(window: weeklyWindow, period: .weekly, now: now)
        fiveHourMenuBarImage = QuotaBadge.image(window: fiveHourWindow, period: .fiveHour, now: now)
    }

    private func clearLogin() {
        loginTimeout?.cancel()
        loginTimeout = nil
        if isSigningIn { authentication = .signedOut }
    }

    private func cancelPendingWork() {
        connectionTask?.cancel()
        loginTask?.cancel()
        accountTask?.cancel()
        polling?.cancel()
        loginTimeout?.cancel()
        accountOperationID = nil
    }

    func shutdown() async {
        let tasks = [connectionTask, loginTask, accountTask].compactMap { $0 }
        cancelPendingWork()
        clearLogin()
        connection = .disconnected
        clearAccount()
        await session.stop()
        for task in tasks { await task.value }
    }
}
