import Foundation
import Observation

enum MenuBarStyle: String, CaseIterable {
    case fullColor, monochrome

    var title: String {
        self == .fullColor ? "Full color" : "Monochrome, baby!"
    }
}

enum MenuBarPanel: String, CaseIterable {
    case combined, fiveHour, weekly, resetExpiration

    var title: String {
        switch self {
        case .combined: "Weekly quota + Banked reset expiration"
        case .weekly: "Weekly quota"
        case .fiveHour: "5-hour quota"
        case .resetExpiration: "Banked reset expiration"
        }
    }

    var autosaveName: String { "UseYourTokens.\(rawValue)" }

    static let bankedResetsExplanation = "Banked resets are free or promotional one-time resets saved to your account that you can manually redeem whenever you choose. They can expire."

    var includesBankedResets: Bool {
        self == .combined || self == .resetExpiration
    }
}

@Observable
@MainActor
final class MenuBarPreferences {
    private(set) var enabled: Set<MenuBarPanel>
    private(set) var refreshIntervalMinutes: Int
    private(set) var style: MenuBarStyle
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "enabledMenuBarPanels"
    private static let refreshKey = "refreshIntervalMinutes"
    private static let styleKey = "menuBarStyle"
    static let refreshIntervals = [1, 2, 5, 10, 15, 30, 45, 60]
    private static let defaultPanels: Set<MenuBarPanel> = [.combined, .fiveHour]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = defaults.string(forKey: Self.styleKey).flatMap(MenuBarStyle.init(rawValue:)) ?? .fullColor
        let savedInterval = defaults.object(forKey: Self.refreshKey) as? Int ?? 5
        refreshIntervalMinutes = Self.clampedInterval(savedInterval)
        if let saved = defaults.stringArray(forKey: Self.key) {
            let restored = Set(saved.compactMap(MenuBarPanel.init(rawValue:)))
            enabled = restored.isEmpty ? Self.defaultPanels : restored
        } else {
            enabled = Self.defaultPanels
        }
    }

    func setStyle(_ value: MenuBarStyle) {
        style = value
        defaults.set(value.rawValue, forKey: Self.styleKey)
    }

    func setRefreshIntervalMinutes(_ value: Int) {
        refreshIntervalMinutes = Self.clampedInterval(value)
        defaults.set(refreshIntervalMinutes, forKey: Self.refreshKey)
    }

    private static func clampedInterval(_ value: Int) -> Int {
        let bounded = min(60, max(1, value))
        return refreshIntervals.min { abs($0 - bounded) < abs($1 - bounded) } ?? 5
    }

    func isEnabled(_ panel: MenuBarPanel) -> Bool { enabled.contains(panel) }

    func canToggle(_ panel: MenuBarPanel) -> Bool {
        !isEnabled(panel) || enabled.count > 1
    }

    func setEnabled(_ value: Bool, for panel: MenuBarPanel) {
        guard value || canToggle(panel) else { return }
        if value { enabled.insert(panel) } else { enabled.remove(panel) }
        defaults.set(enabled.map(\.rawValue).sorted(), forKey: Self.key)
    }
}
