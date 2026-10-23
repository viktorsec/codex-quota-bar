import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        Text("Codex Quota Bar")
        Text("Quota not connected yet")

        Divider()

        Button("Quit Codex Quota Bar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

#Preview {
    ContentView()
}
