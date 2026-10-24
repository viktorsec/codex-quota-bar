import CryptoKit
import Foundation

/// The signed broker returns only an exit status; no token bytes cross pipes.
enum CredentialAccess {
    enum State: Sendable { case trusted, signedOut, requiresSignIn }
    // Wire contract shared with HelperSources/CredentialStore.h.
    enum ExitStatus: Int32 {
        case ready = 0
        case signedOut = 10
        case signInRequired = 20
        case keychainLocked = 21
        case storageUnavailable = 22
    }
    enum AccessError: LocalizedError {
        case locked, unavailable(Int32)
        var errorDescription: String? {
            switch self {
            case .locked:
                "Your login Keychain is locked. Unlock it in Keychain Access, then reconnect. Your saved sign-in has been kept."
            case .unavailable(let status):
                "Could not access secure sign-in storage (error \(status)). Reconnect to try again."
            }
        }
    }

    @concurrent
    static func inspect(home: URL, helper: URL) async throws -> State {
        // Matches compute_store_key in the pinned Codex direct-Keychain backend.
        let path = home.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8))
        let account = "cli|" + digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        let status = try await run(helper: helper, arguments: [String(account)])
        switch ExitStatus(rawValue: status) {
        case .ready: return .trusted
        case .signedOut: return .signedOut
        case .signInRequired: return .requiresSignIn
        case .keychainLocked: throw AccessError.locked
        default: throw AccessError.unavailable(status)
        }
    }

    #if DEBUG
    @concurrent
    static func selfTest(helper: URL) async throws {
        let status = try await run(helper: helper, arguments: ["--self-test"])
        guard status == EXIT_SUCCESS else { throw AccessError.unavailable(status) }
    }
    #endif

    @concurrent
    private static func run(helper: URL, arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = helper.deletingLastPathComponent().appending(path: "CodexQuotaBarCredentialStore")
        process.arguments = arguments
        process.environment = [
            "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(),
            "PATH": "/usr/bin:/bin"
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            if process.isRunning { process.terminate() }
        }
        defer { timeout.cancel() }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { @Sendable child in
                    continuation.resume(returning: child.terminationStatus)
                }
                do { try process.run() }
                catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        return status
    }
}
