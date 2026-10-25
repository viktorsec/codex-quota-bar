#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum MenuBarSettingsCheck {
    static func run() async throws {
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
        try require(title.gestureRecognizers.contains {
            ($0 as? NSClickGestureRecognizer)?.numberOfClicksRequired == 3
        }, "Secret window gesture is attached to the Settings title")
        delegate.showSettings()
        try require(NSApp.windows.filter { $0.title == "Codex Quota Bar Settings" }.count == 1, "Settings reuses its window")
        window.close()
        try require(!window.isVisible, "Settings closes")
        delegate.showSettings()
        try require(window.isVisible, "Settings reopens the existing window")
        window.close()
        print("PASS: Settings opens, reuses its window, and reopens after closing")

        let originalWeekly = delegate.model.weeklyMenuBarImage.accessibilityDescription
        let originalFiveHour = delegate.model.fiveHourMenuBarImage.accessibilityDescription
        let originalCredits = delegate.model.resetExpirationMenuBarImage.accessibilityDescription
        let liveWindowIDs = delegate.model.windows.map(\.id)
        delegate.showSecretWindow()
        guard let secret = NSApp.windows.first(where: { $0.title == "Secret Window" }) else {
            throw NSError(domain: "MenuBarSettingsCheck", code: 5)
        }
        try await waitUntil({ secret.isKeyWindow }, message: "Secret Window did not become key")
        guard let secretTitlebar = secret.titlebarAccessoryViewControllers.first?.view,
              let secretTitle = secretTitlebar.subviews.first(where: { $0.identifier?.rawValue == "secret-window-title" }) else {
            throw NSError(domain: "MenuBarSettingsCheck", code: 7)
        }
        secretTitlebar.layoutSubtreeIfNeeded()
        try require(abs(secretTitle.convert(secretTitle.bounds, to: nil).midX - secret.frame.width / 2) < 1,
                    "Secret Window title is centered across the full window width")
        print("PASS: Secret Window title is centered across the full window width")
        delegate.showSecretWindow()
        try require(NSApp.windows.filter { $0.title == "Secret Window" }.count == 1, "Secret window is reused")
        guard let editingSession = delegate.model.simulation else {
            throw NSError(domain: "MenuBarSettingsCheck", code: 6)
        }
        @Bindable var editing = editingSession
        let outgoingSlider = $editing.weeklyRemainingPercent
        delegate.model.simulation?.weeklyRemainingPercent = 9
        delegate.model.simulation?.fiveHourRemainingPercent = 4
        delegate.model.simulation?.bankedResets = []
        try require(delegate.model.weeklyMenuBarImage.accessibilityDescription?.contains("9% remaining") == true, "Weekly preview updates immediately")
        try require(delegate.model.fiveHourMenuBarImage.accessibilityDescription?.contains("4% remaining") == true, "5-hour preview updates immediately")
        try require(delegate.model.resetExpirationMenuBarImage.accessibilityDescription == "No banked resets left", "Banked reset preview updates immediately")
        try require(delegate.model.windows.map(\.id) == liveWindowIDs, "Simulation preserves live quota data")
        secret.close()
        try require(delegate.model.simulation == nil, "Closing Secret Window ends simulation")
        // Let the outgoing SwiftUI graph run its layout and binding updates
        // before reopening. The optional binding previously trapped here.
        secret.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try require(outgoingSlider.wrappedValue == 9, "Outgoing slider remains safe after closing")
        outgoingSlider.wrappedValue = 88
        try require(delegate.model.simulation == nil, "Late control updates cannot restart simulation")
        try require(delegate.model.weeklyMenuBarImage.accessibilityDescription == originalWeekly &&
                    delegate.model.fiveHourMenuBarImage.accessibilityDescription == originalFiveHour &&
                    delegate.model.resetExpirationMenuBarImage.accessibilityDescription == originalCredits,
                    "Closing restores live menu bar values")
        delegate.showSecretWindow()
        try require(secret.isVisible, "Secret window reopens")
        try require(delegate.model.simulation?.weeklyRemainingPercent != 9, "Reopening discards previous edits")
        let newPercentage = delegate.model.simulation?.weeklyRemainingPercent
        outgoingSlider.wrappedValue = 67
        try require(delegate.model.simulation?.weeklyRemainingPercent == newPercentage, "Old bindings cannot change a new editing session")
        delegate.showSettings()
        try await waitUntil({ delegate.model.simulation == nil }, message: "Leaving Secret Window ends simulation")
        secret.makeKeyAndOrderFront(nil)
        try await waitUntil({ delegate.model.simulation != nil }, message: "Returning starts a fresh simulation")
        secret.close()
        window.close()
        print("PASS: secret window opens once and reopens after closing")
        print("PASS: simulation updates previews without changing live data and resets on close or focus loss")
        for _ in 0..<3 {
            delegate.showSecretWindow()
            try await waitUntil({ secret.isKeyWindow }, message: "Secret Window did not become key")
            delegate.model.simulation?.bankedResets = [.init(expiresAt: .now.addingTimeInterval(3_600))]
            secret.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            delegate.model.simulation?.bankedResets.removeAll()
            secret.close()
            secret.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            try require(delegate.model.simulation == nil, "Repeated close clears simulation safely")
        }
        print("PASS: closing, delayed slider updates, and removing banked reset rows stay safe across repeated sessions")
    }

    private static func waitUntil(_ condition: () -> Bool, message: String) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            try require(ContinuousClock.now < deadline, message)
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw NSError(domain: "MenuBarSettingsCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
#endif
