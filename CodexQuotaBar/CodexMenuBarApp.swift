import SwiftUI
import AppKit

@main struct CodexMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: delegate.model)
        } label: {
            Image(nsImage: delegate.model.menuBarImage)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = QuotaModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") ||
            ProcessInfo.processInfo.arguments.contains("--check-saved-sign-in") ||
            ProcessInfo.processInfo.arguments.contains("--credential-self-test") ||
            ProcessInfo.processInfo.arguments.contains("--check-model-state") {
            Task { await HelperSmokeCheck.run() }
            return
        }
        #endif
        model.connect()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
