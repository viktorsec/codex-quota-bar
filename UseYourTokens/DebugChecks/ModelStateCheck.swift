#if DEBUG
import Foundation

/// Exercises real model transitions using this app's saved login, without UI.
@MainActor
enum ModelStateCheck {
    static func run() async throws {
        let model = QuotaModel()
        try require(model.connection == .disconnected && !model.isSignedIn, "Initial state")
        do {
            model.connect()
            try require(model.isConnecting, "Connection begins synchronously")
            try await waitUntil({ !model.isConnecting }, failure: "Connection did not finish")
            try require(model.isConnected && model.isSignedIn && model.updatedAt != nil, "Saved account restoration")
            print("PASS: explicit connection state restores the saved account and quota")

            model.refresh()
            try require(model.isRefreshing, "Refresh begins synchronously")
            try await waitUntil({ !model.isRefreshing }, failure: "Refresh did not finish")
            try require(model.isConnected && model.isSignedIn && model.errorMessage == nil, "Refresh preserves authentication")
            print("PASS: refresh preserves the connected, signed-in state")

            await model.shutdown()
            try require(model.connection == .disconnected && !model.isSignedIn && model.windows.isEmpty && !model.isRefreshing, "Shutdown clears model state")
            model.connect()
            await model.shutdown()
            // A cancelled startup must settle without changing the stopped state.
            try require(model.connection == .disconnected && !model.isSignedIn, "Cancelled connection remains stopped")
            print("PASS: shutdown and cancelled connection return to the disconnected state")
        } catch {
            await model.shutdown()
            throw error
        }
    }

    private static func waitUntil(_ condition: () -> Bool, failure: String) async throws {
        let deadline = ContinuousClock.now + .seconds(45)
        while !condition() {
            try require(ContinuousClock.now < deadline, failure)
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckError.failed(message) }
    }

    private enum CheckError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self { case .failed(let message): message }
        }
    }
}
#endif
