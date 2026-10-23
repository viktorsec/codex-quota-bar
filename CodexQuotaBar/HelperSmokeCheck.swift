#if DEBUG
import AppKit

/// Run the real signed app with --smoke-test to exercise helper packaging,
/// sandbox inheritance, account access, and the local OAuth callback listener.
/// Never opens a browser, reads existing Codex credentials, or logs auth URLs.
@MainActor
enum HelperSmokeCheck {
    static func run() async {
        let client = CodexClient()
        do {
            guard NSHomeDirectory().contains("/Library/Containers/") else {
                throw CheckError.failed("App is not running in a sandbox container")
            }
            print("PASS: app uses a sandbox container")
            try await client.start()
            print("PASS: bundled helper initialized")
            let account = try await client.request("account/read", params: ["refreshToken": false])
            guard account.keys.contains("account") else {
                throw CheckError.failed("Account response is missing")
            }
            print("PASS: account state read without an external CLI")
            let login = try await client.request("account/login/start", params: ["type": "chatgpt"])
            guard let loginID = login["loginId"] as? String,
                  let url = login["authUrl"] as? String, url.hasPrefix("https://") else {
                throw CheckError.failed("Browser login did not return a URL and login identifier")
            }
            print("PASS: browser login started inside the sandbox")
            _ = try await client.request("account/login/cancel", params: ["loginId": loginID])
            print("PASS: browser login cancelled")
            await client.stop()
            print("PASS: helper shut down")
            fflush(stdout)
            exit(0)
        } catch {
            await client.stop()
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
