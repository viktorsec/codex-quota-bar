#if DEBUG
import AppKit

@MainActor
enum MenuBarSettingsCheck {
    static func run() throws {
        let suite = "CodexQuotaBar.SettingsCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MenuBarPreferences(defaults: defaults)
        try require(preferences.refreshIntervalMinutes == 5, "Default refresh interval")
        preferences.setRefreshIntervalMinutes(0)
        try require(preferences.refreshIntervalMinutes == 1, "Fastest automatic refresh is once per minute")
        preferences.setRefreshIntervalMinutes(90)
        try require(preferences.refreshIntervalMinutes == 60, "Refresh interval upper bound")
        preferences.setRefreshIntervalMinutes(22)
        try require(preferences.refreshIntervalMinutes == 15, "Refresh interval snaps to a supported step")
        preferences.setRefreshIntervalMinutes(30)
        try require(MenuBarPreferences(defaults: defaults).refreshIntervalMinutes == 30, "Refresh interval survives relaunch")
        print("PASS: refresh interval persists and uses supported steps from 1 minute to 1 hour")
        try require(preferences.enabled == [.combined, .fiveHour], "Default panels")
        preferences.setEnabled(true, for: .resetExpiration)
        preferences.setEnabled(false, for: .combined)
        preferences.setEnabled(false, for: .fiveHour)
        preferences.setEnabled(false, for: .resetExpiration)
        try require(preferences.enabled == [.resetExpiration], "Last panel cannot be disabled")
        try require(!preferences.canToggle(.resetExpiration) && preferences.canToggle(.weekly), "Toggle availability")
        try require(MenuBarPreferences(defaults: defaults).enabled == [.resetExpiration], "Preferences survive relaunch")
        defaults.set([], forKey: "enabledMenuBarPanels")
        try require(MenuBarPreferences(defaults: defaults).enabled == [.combined, .fiveHour], "Empty preferences recover default panels")
        defaults.set(["weekly", "resetExpiration"], forKey: "enabledMenuBarPanels")
        try require(MenuBarPreferences(defaults: defaults).enabled == [.weekly, .resetExpiration], "Existing custom choices are preserved")
        print("PASS: panel preferences persist and always keep at least one enabled")

        let name = "CodexQuotaBar.PositionCheck.\(UUID().uuidString)"
        let positionKey = "NSStatusItem Preferred Position \(name)"
        let visibleKey = "NSStatusItem Visible \(name)"
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = name
        defer {
            NSStatusBar.system.removeStatusItem(item)
            UserDefaults.standard.removeObject(forKey: positionKey)
            UserDefaults.standard.removeObject(forKey: visibleKey)
        }
        UserDefaults.standard.set(7, forKey: positionKey)
        MenuBarController.setVisible(false, item: item)
        try require(!item.isVisible && UserDefaults.standard.integer(forKey: positionKey) == 7, "Hiding preserves preferred position")
        MenuBarController.setVisible(true, item: item)
        try require(item.isVisible && UserDefaults.standard.integer(forKey: positionKey) == 7, "Showing reuses preferred position")
        print("PASS: native status-item hide/show preserves the saved position")

        let now = Date(timeIntervalSince1970: 1_000)
        let credits = ResetCredits(availableCount: 3, credits: [
            .init(id: "expired", expiresAt: now.addingTimeInterval(-1)),
            .init(id: "later", expiresAt: now.addingTimeInterval(3_600)),
            .init(id: "next", expiresAt: now.addingTimeInterval(60))
        ])
        try require(credits.nextExpiration(after: now) == now.addingTimeInterval(60), "Next unexpired reset")
        try require(ResetCredits(availableCount: 0, credits: credits.credits).nextExpiration(after: now) == nil, "Zero count overrides stale detail rows")
        try require(ResetCredits(availableCount: 1, credits: [.init(id: "unknown", expiresAt: nil)]).nextExpiration(after: now) == nil, "Missing expiration")
        try require(QuotaBadge.resetExpirationImage(credits: nil, now: now).size.width > 0, "Unknown reset remains reachable")
        print("PASS: reset countdown selects the next unexpired credit and handles missing details")

        let weekly = QuotaWindow(id: "codex.secondary", title: "Weekly", usedPercent: 25,
                                 resetsAt: now.addingTimeInterval(120), windowDurationMins: 10_080)
        let laterCredits = ResetCredits(availableCount: 1, credits: [
            .init(id: "later", expiresAt: now.addingTimeInterval(240))
        ])
        try require(QuotaBadge.combinedResetDate(window: weekly, credits: credits, now: now) == now.addingTimeInterval(60), "Expiration before weekly reset")
        try require(QuotaBadge.combinedResetDate(window: weekly, credits: laterCredits, now: now) == weekly.resetsAt, "Weekly reset before expiration")
        try require(QuotaBadge.combinedResetDate(window: weekly, credits: nil, now: now) == weekly.resetsAt, "Weekly reset without credits")
        try require(QuotaBadge.combinedResetDate(window: nil, credits: credits, now: now) == now.addingTimeInterval(60), "Expiration without weekly data")
        try require(QuotaBadge.combinedResetDate(window: nil, credits: nil, now: now) == nil, "No reset dates")
        print("PASS: combined countdown uses the earlier weekly reset or available credit expiration")

        guard let delegate = NSApp.delegate as? AppDelegate else {
            throw NSError(domain: "MenuBarSettingsCheck", code: 2)
        }
        delegate.showSettings()
        guard let window = NSApp.windows.first(where: { $0.title == "Codex Quota Bar Settings" }) else {
            throw NSError(domain: "MenuBarSettingsCheck", code: 3)
        }
        guard let titlebar = window.titlebarAccessoryViewControllers.first?.view,
              let title = titlebar.subviews.first(where: { $0.identifier?.rawValue == "settings-window-title" }) else {
            throw NSError(domain: "MenuBarSettingsCheck", code: 4)
        }
        titlebar.layoutSubtreeIfNeeded()
        let titleCenter = title.convert(title.bounds, to: nil).midX
        try require(abs(titleCenter - window.frame.width / 2) < 1, "Settings title center \(titleCenter), window width \(window.frame.width), titlebar frame \(titlebar.frame), title frame \(title.frame)")
        print("PASS: Settings title is centered across the full window width")
        delegate.showSettings()
        try require(NSApp.windows.filter { $0.title == "Codex Quota Bar Settings" }.count == 1, "Settings reuses its window")
        window.close()
        try require(!window.isVisible, "Settings closes")
        delegate.showSettings()
        try require(window.isVisible, "Settings reopens the existing window")
        window.close()
        print("PASS: Settings opens, reuses its window, and reopens after closing")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw NSError(domain: "MenuBarSettingsCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
#endif
