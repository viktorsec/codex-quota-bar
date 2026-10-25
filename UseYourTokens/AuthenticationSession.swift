import Foundation

/// Owns credential selection and recovery. CodexClient only transports RPCs.
@MainActor
final class AuthenticationSession {
    enum SessionError: LocalizedError {
        case savedSignInUnavailable
        var errorDescription: String? {
            "Your saved sign-in is unavailable. Reconnect to sign in again."
        }
    }

    static var accountHelperURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/UseYourTokensAccountHelper")
    }

    var onNotification: ((String, [String: Any]) -> Void)? {
        didSet { client.onNotification = onNotification }
    }
    var onDisconnect: (() -> Void)? {
        didSet { client.onDisconnect = onDisconnect }
    }
    var isConnected: Bool { client.isConnected }
    private(set) var credentialNotice: String?
    private let client = CodexClient()
    private var credentialHome: URL?

    func start() async throws {
        let home = try await prepareCredentials()
        credentialHome = home
        try await client.start(configuration: .init(
            executable: Self.accountHelperURL,
            workingDirectory: home,
            arguments: [
                "--listen", "stdio://",
                "-c", "cli_auth_credentials_store=\"keyring\"",
                // The gate matches this pinned direct-Keychain backend.
                "-c", "features.secret_auth_storage=false",
                "-c", "forced_login_method=\"chatgpt\""
            ],
            // Never inherit API keys, tokens, or the user's CODEX_HOME.
            environment: [
                "HOME": NSHomeDirectory(), "CODEX_HOME": home.path,
                "TMPDIR": NSTemporaryDirectory(), "PATH": "/usr/bin:/bin",
                "LANG": "en_US.UTF-8", "RUST_LOG": "error"
            ]
        ))
    }

    func request(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard client.isConnected else { throw CodexClient.ClientError.disconnected }
        if method.hasPrefix("account/"), method != "account/login/cancel", let credentialHome {
            let access = try await CredentialAccess.inspect(home: credentialHome, helper: Self.accountHelperURL)
            if access == .signedOut, method == "account/read" {
                // A pre-created entry grants access but has no account token.
                // Keep this upstream compatibility rule out of the transport.
                return ["account": NSNull(), "requiresOpenaiAuth": true]
            }
            if access == .requiresSignIn {
                await client.stop()
                onDisconnect?()
                throw SessionError.savedSignInUnavailable
            }
        }
        return try await client.request(method, params: params)
    }

    func stop() async {
        await client.stop()
        credentialHome = nil
    }

    private func prepareCredentials() async throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appending(path: "UseYourTokens/Authentication", directoryHint: .isDirectory)
        let key = "authenticationStoreGeneration"
        let stored = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:))
        var generation = stored ?? UUID()
        var home = try createSlot(generation, under: root)
        credentialNotice = nil
        if try await CredentialAccess.inspect(home: home, helper: Self.accountHelperURL) == .requiresSignIn {
            generation = UUID()
            home = try createSlot(generation, under: root)
            guard try await CredentialAccess.inspect(home: home, helper: Self.accountHelperURL) == .signedOut else {
                throw CredentialAccess.AccessError.unavailable(CredentialAccess.ExitStatus.storageUnavailable.rawValue)
            }
            credentialNotice = "Your previous saved sign-in is unavailable. Please sign in again."
        }
        try Task.checkCancellation()
        // This is a non-secret selector, never a credential or token.
        UserDefaults.standard.set(generation.uuidString, forKey: key)
        return home
    }

    private func createSlot(_ generation: UUID, under root: URL) throws -> URL {
        let home = root.appending(path: generation.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        return home
    }
}
