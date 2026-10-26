import SwiftUI
import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSGestureRecognizerDelegate, NSWindowDelegate {
    let preferences = MenuBarPreferences()
    private(set) lazy var model = QuotaModel(preferences: preferences)
    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindowController?
    private var secretWindow: NSWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") ||
            ProcessInfo.processInfo.arguments.contains("--check-saved-sign-in") ||
            ProcessInfo.processInfo.arguments.contains("--credential-self-test") ||
            ProcessInfo.processInfo.arguments.contains("--check-model-state") ||
            ProcessInfo.processInfo.arguments.contains("--check-menu-bar-settings") ||
            ProcessInfo.processInfo.arguments.contains("--check-quota-refills") {
            Task { await HelperSmokeCheck.run() }
            return
        }
        #endif
        configureMainMenu()
        menuBar = MenuBarController(model: model, preferences: preferences) { [weak self] in
            self?.showSettings()
        }
        model.connect()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshAfterWake), name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    @objc private func refreshAfterWake() { model.refresh() }

    @objc func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(preferences: preferences, model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Use Your Tokens Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            configureCenteredTitlebar(window, opensSecretWindow: true)
            window.isReleasedWhenClosed = false
            // Resolve the hosted view's size before choosing a screen position.
            // Otherwise its first layout can resize an already-centered window.
            hosting.view.layoutSubtreeIfNeeded()
            let restored = window.setFrameUsingName("Settings", force: true)
            window.setContentSize(hosting.view.fittingSize)
            if !restored { window.center() }
            window.setFrameAutosaveName("Settings")
            let controller = NSWindowController(window: window)
            controller.shouldCascadeWindows = false
            settingsWindow = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func configureCenteredTitlebar(_ window: NSWindow, opensSecretWindow: Bool = false) {
        window.titleVisibility = .hidden
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .top
        accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 40))

        let title = NSTextField(labelWithString: window.title)
        title.identifier = NSUserInterfaceItemIdentifier(opensSecretWindow ? "settings-window-title" : "secret-window-title")
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        if opensSecretWindow {
            let secretClick = NSClickGestureRecognizer(target: self, action: #selector(handleSecretTitleClick(_:)))
            secretClick.numberOfClicksRequired = 3
            secretClick.delegate = self
            secretClick.delaysPrimaryMouseButtonEvents = true
            title.addGestureRecognizer(secretClick)
        }
        accessory.view.addSubview(title)
        window.addTitlebarAccessoryViewController(accessory)
        NSLayoutConstraint.activate([
            title.centerYAnchor.constraint(equalTo: accessory.view.centerYAnchor),
            title.widthAnchor.constraint(lessThanOrEqualTo: accessory.view.widthAnchor, constant: -180)
        ])
        if let content = window.contentView {
            // AppKit offsets the accessory around the traffic-light controls.
            // Center against the full content width, not the accessory's width.
            title.centerXAnchor.constraint(equalTo: content.centerXAnchor).isActive = true
        }
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        event.modifierFlags.contains(.option)
    }

    @objc private func handleSecretTitleClick(_ recognizer: NSClickGestureRecognizer) {
        guard NSApp.currentEvent?.modifierFlags.contains(.option) == true else { return }
        showSecretWindow()
    }

    func showSecretWindow() {
        model.beginSimulation()
        if secretWindow == nil {
            let hosting = NSHostingController(rootView: SecretWindowView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Secret Window"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            configureCenteredTitlebar(window)
            window.isReleasedWhenClosed = false
            window.delegate = self
            hosting.view.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.view.fittingSize)
            window.center()
            let controller = NSWindowController(window: window)
            controller.shouldCascadeWindows = false
            secretWindow = controller
        }
        secretWindow?.showWindow(nil)
        secretWindow?.window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === secretWindow?.window { model.endSimulation() }
    }

    private func configureMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Use Your Tokens")
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Use Your Tokens", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
