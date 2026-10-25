#if DEBUG
import AppKit

/// Run the real signed app with --smoke-test to exercise helper packaging,
/// sandbox inheritance, account access, and the local OAuth callback listener.
/// Never opens a browser or logs credentials/account details. Saved-session
/// checks read only this app's own credential slot, never another Codex install.
@MainActor
enum HelperSmokeCheck {
    static func run() async {
        let session = AuthenticationSession()
        do {
            if ProcessInfo.processInfo.arguments.contains("--check-menu-bar-settings") {
                try MenuBarSettingsCheck.run()
                fflush(stdout)
                exit(0)
            }
            if ProcessInfo.processInfo.arguments.contains("--check-model-state") {
                try await ModelStateCheck.run()
                fflush(stdout)
                exit(0)
            }
            if ProcessInfo.processInfo.arguments.contains("--credential-self-test") {
                let helper = AuthenticationSession.accountHelperURL
                try await CredentialAccess.selfTest(helper: helper)
                print("PASS: create/reuse credentials, preserve access after update, reject changed helper identity, reject denied access without UI, remove test fixture")
                fflush(stdout)
                exit(0)
            }
            guard NSHomeDirectory().contains("/Library/Containers/") else {
                throw CheckError.failed("App is not running in a sandbox container")
            }
            print("PASS: app uses a sandbox container")
            try await session.start()
            print("PASS: bundled helper initialized")
            let account = try await session.request("account/read", params: ["refreshToken": false])
            guard account.keys.contains("account") else {
                throw CheckError.failed("Account response is missing")
            }
            print("PASS: persistent account storage checked without requesting Keychain UI")
            if ProcessInfo.processInfo.arguments.contains("--check-saved-sign-in") {
                guard let savedAccount = account["account"] as? [String: Any],
                      savedAccount["type"] as? String == "chatgpt" else {
                    throw CheckError.failed("Browser sign-in was not restored in a fresh process")
                }
                print("PASS: saved browser sign-in restored in a fresh process")
                _ = try await session.request("account/rateLimits/read")
                print("PASS: live quota retrieved using the restored sign-in")
                await session.stop()
                fflush(stdout)
                exit(0)
            }
            let login = try await session.request("account/login/start", params: ["type": "chatgpt"])
            guard let loginID = login["loginId"] as? String,
                  let url = login["authUrl"] as? String, url.hasPrefix("https://") else {
                throw CheckError.failed("Browser login did not return a URL and login identifier")
            }
            print("PASS: browser login started inside the sandbox")
            _ = try await session.request("account/login/cancel", params: ["loginId": loginID])
            print("PASS: browser login cancelled")
            await session.stop()
            print("PASS: helper shut down")
            fflush(stdout)
            exit(0)
        } catch {
            await session.stop()
            print("FAIL: \(error.localizedDescription)")
            fflush(stdout)
            exit(1)
        }
    }

    private enum CheckError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self { case .failed(let message): message }
        }
    }
}
#endif
