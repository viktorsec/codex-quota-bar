import SwiftUI
import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = MenuBarPreferences()
    private(set) lazy var model = QuotaModel(preferences: preferences)
    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindowController?

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
            ProcessInfo.processInfo.arguments.contains("--check-menu-bar-settings") {
            Task { await HelperSmokeCheck.run() }
            return
        }
        #endif
        configureMainMenu()
        menuBar = MenuBarController(model: model, preferences: preferences) { [weak self] in
            self?.showSettings()
        }
        model.connect()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(preferences: preferences, model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Codex Quota Bar Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            configureSettingsTitlebar(window)
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

    private func configureSettingsTitlebar(_ window: NSWindow) {
        window.titleVisibility = .hidden
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .top
        accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 40))

        let title = NSTextField(labelWithString: window.title)
        title.identifier = NSUserInterfaceItemIdentifier("settings-window-title")
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
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

    private func configureMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Codex Quota Bar")
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Codex Quota Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
