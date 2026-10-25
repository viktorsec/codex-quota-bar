import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarController {
    private let model: QuotaModel
    private let preferences: MenuBarPreferences
    private var items: [MenuBarPanel: NSStatusItem] = [:]

    init(model: QuotaModel, preferences: MenuBarPreferences, openSettings: @escaping () -> Void) {
        self.model = model
        self.preferences = preferences
        for panel in MenuBarPanel.allCases {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = panel.autosaveName
            // Only Settings controls removal, so Command-drag cannot leave the
            // user without a way to reach the app.
            item.behavior = []
            item.menu = NSHostingMenu(rootView: ContentView(model: model, openSettings: openSettings))
            items[panel] = item
        }
        observeChanges()
    }

    private func observeChanges() {
        withObservationTracking {
            for panel in MenuBarPanel.allCases {
                guard let item = items[panel] else { continue }
                let image: NSImage
                switch panel {
                case .combined: image = model.combinedMenuBarImage
                case .weekly: image = model.weeklyMenuBarImage
                case .fiveHour: image = model.fiveHourMenuBarImage
                case .resetExpiration: image = model.resetExpirationMenuBarImage
                }
                item.button?.image = QuotaBadge.styled(image, style: preferences.style)
                item.button?.setAccessibilityLabel(image.accessibilityDescription)
                Self.setVisible(preferences.isEnabled(panel), item: item)
            }
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.observeChanges() }
        }
    }

    static func setVisible(_ visible: Bool, item: NSStatusItem, defaults: UserDefaults = .standard) {
        guard item.isVisible != visible else { return }
        // AppKit removes its preferred-position preference when hiding an item.
        // Preserve that one value so showing the same autosave identity restores
        // its position. Keep this compatibility detail isolated here.
        let key = "NSStatusItem Preferred Position \(item.autosaveName!)"
        let position = defaults.object(forKey: key)
        item.isVisible = visible
        if !visible, let position { defaults.set(position, forKey: key) }
    }
}
