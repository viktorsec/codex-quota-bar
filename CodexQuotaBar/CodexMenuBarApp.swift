import SwiftUI

@main struct CodexMenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("Codex Quota", systemImage: "gauge.medium") {
            ContentView()
        }
        .menuBarExtraStyle(.menu)
    }
}
