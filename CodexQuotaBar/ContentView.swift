import SwiftUI
import AppKit

struct ContentView: View {
    let model: QuotaModel

    var body: some View {
        Text("Codex Quota Bar")

        if model.isConnecting {
            Text("Connecting…")
        } else if !model.isConnected {
            Button("Reconnect", action: model.connect)
        } else if model.isSigningIn {
            Text("Complete sign-in in your browser")
            Button("Open Sign-In Page", action: model.reopenSignIn)
            Button("Cancel Sign-In", action: model.cancelSignIn)
        } else if model.isSignedIn {
            if let email = model.email { Text(email) }
            if model.windows.isEmpty {
                Text("No quota information available")
            }
            ForEach(model.windows) { window in
                Text("\(window.title): \(window.remainingPercent)% remaining")
                if let reset = window.resetsAt {
                    Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            if let updated = model.updatedAt {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
            }
            Divider()
            Button(model.isRefreshing ? "Refreshing…" : "Refresh", action: model.refresh)
                .disabled(model.isRefreshing)
            Button("Sign Out", action: model.signOut)
                .disabled(model.isRefreshing)
        } else {
            Button("Sign in with ChatGPT…", action: model.signIn)
        }

        if let error = model.errorMessage {
            Divider()
            Text(error)
        }

        Divider()

        Button("Quit Codex Quota Bar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

#Preview {
    ContentView(model: QuotaModel())
}
