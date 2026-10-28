#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum MenuBarSettingsCheck {
    static func run() async throws {
        let suite = "UseYourTokens.SettingsCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MenuBarPreferences(defaults: defaults)
        try require(preferences.style == .fullColor, "Full color is the default style")
        preferences.setStyle(.monochrome)
        try require(MenuBarPreferences(defaults: defaults).style == .monochrome, "Monochrome style survives relaunch")
        preferences.setStyle(.fullColor)
        try require(MenuBarPreferences(defaults: defaults).style == .fullColor, "Full color can be restored")
        defaults.set("unknown-style", forKey: "menuBarStyle")
        try require(MenuBarPreferences(defaults: defaults).style == .fullColor, "Unknown style defaults to full color")
        preferences.setStyle(.fullColor)
        print("PASS: menu bar style defaults to full color and persists both choices")
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

        let name = "UseYourTokens.PositionCheck.\(UUID().uuidString)"
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
        let countdownCases: [(TimeInterval, String)] = [
            (3 * 86_400, "3d"), (3 * 86_400 - 1, "3d"),
            (2 * 86_400 + 1, "3d"), (2 * 86_400, "48h"), (2 * 86_400 - 1, "48h"),
            (3 * 3_600, "3h"), (3 * 3_600 - 1, "3h"),
            (2 * 3_600 + 1, "3h"), (2 * 3_600, "120m"), (2 * 3_600 - 1, "120m"),
            (90 * 60, "90m"), (61, "2m"), (60, "1m"), (1, "1m"), (0, "Now"), (-1, "Now")
        ]
        for (seconds, expected) in countdownCases {
            try require(QuotaBadge.countdown(until: now.addingTimeInterval(seconds), period: .weekly, now: now) == expected,
                        "Rounded countdown at \(seconds) seconds should be \(expected)")
        }
        try require(QuotaBadge.countdown(until: nil, period: .weekly, now: now) == "—", "Missing weekly deadline")
        try require(QuotaBadge.countdown(until: now.addingTimeInterval(90 * 60), period: .fiveHour, now: now) == "01:30",
                    "5-hour countdown keeps hours and minutes")
        print("PASS: countdowns round up and switch units at exactly 48 hours and 120 minutes")

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
        let combined = QuotaBadge.combinedImage(window: weekly, credits: credits, now: now)
        try require(combined.accessibilityDescription?.contains("Weekly reset:") == true &&
                    combined.accessibilityDescription?.contains("Banked reset expiration:") == true,
                    "Combined badge describes both deadlines")
        try require(combined.size.width > QuotaBadge.image(window: weekly, period: .weekly, now: now).size.width,
                    "Combined badge makes room for side-by-side countdowns")
        let noBanked = QuotaBadge.combinedImage(window: weekly, credits: ResetCredits(availableCount: 0, credits: []), now: now)
        try require(noBanked.accessibilityDescription?.contains("No banked resets left.") == true,
                    "Combined badge distinguishes no banked resets from unavailable data")
        try require(noBanked.size == QuotaBadge.image(window: weekly, period: .weekly, now: now).size,
                    "Zero banked resets removes the divider, coupon, and countdown without leaving extra space")
        print("PASS: combined badge includes both deadlines and handles missing banked resets")

        let warningCases: [(Double, QuotaBadge.Urgency?)] = [
            (5 * 86_400 + 1, nil), (5 * 86_400, .yellow),
            (4 * 86_400 + 1, .yellow), (4 * 86_400, .orange),
            (60 * 3_600 + 1, .orange), (60 * 3_600, .red), (60, .red),
            (0, nil), (-1, nil)
        ]
        for (seconds, expected) in warningCases {
            try require(QuotaBadge.expirationUrgency(until: now.addingTimeInterval(seconds), now: now) == expected,
                        "Banked reset urgency at \(seconds) seconds")
        }
        try require(QuotaBadge.expirationUrgency(until: nil, now: now) == nil, "Unknown expiration has no warning color")
        try require(!QuotaBadge.resetExpirationImage(credits: credits, now: now).isTemplate, "Urgent badges preserve their countdown color")
        print("PASS: Banked reset colors honor the 5-day, 4-day, and 60-hour boundaries")

        func weeklyWindow(remaining: Int, days: Double?) -> QuotaWindow {
            QuotaWindow(id: "test.weekly", title: "Weekly", usedPercent: Double(100 - remaining),
                        resetsAt: days.map { now.addingTimeInterval($0 * 86_400) }, windowDurationMins: 10_080)
        }
        let weeklyCases: [(Int, Double?, QuotaBadge.Urgency?)] = [
            (100, 5, .yellow), (100, 4, .orange), (100, 2.5, .red), (100, 2, .red), (100, 1, .red),
            (80, 5, nil), (40, 5, nil), (10, 5, nil),
            (80, 4, .yellow), (80, 2, .red), (80, 1, .red),
            (40, 4, nil), (40, 2, .yellow), (40, 1, .red),
            (10, 4, nil), (10, 2, nil), (10, 1, nil), (10, 1 / 24.0, nil),
            (0, 1 / 24.0, nil), (11, 1 / 24.0, .red),
            (19, 1, nil), (20, 1, .yellow), (24, 1, .yellow),
            (25, 1, .orange), (39, 1, .orange), (40, 1, .red),
            (40, 0.5, .red), (100, 5 + 1 / 86_400.0, nil),
            (80, 0, nil), (80, -1, nil), (80, nil, nil)
        ]
        for (remaining, days, expected) in weeklyCases {
            try require(QuotaBadge.weeklyUrgency(window: weeklyWindow(remaining: remaining, days: days), now: now) == expected,
                        "Weekly urgency with \(remaining)% and \(String(describing: days)) days left")
        }
        try require(QuotaBadge.weeklyUrgency(window: nil, now: now) == nil, "Unknown weekly quota has no warning color")
        let neutralWeekly = weeklyWindow(remaining: 80, days: 5)
        try require(!QuotaBadge.combinedImage(window: neutralWeekly, credits: nil, now: now).isTemplate, "Combined badge preserves its gray divider even without warnings")
        try require(!QuotaBadge.image(window: weekly, period: .weekly, now: now).isTemplate, "Weekly percentage preserves its warning color")
        try require(!QuotaBadge.image(window: weekly, period: .fiveHour, now: now).isTemplate, "5-hour quota preserves its warning color")
        try require(!QuotaBadge.combinedImage(window: weekly, credits: laterCredits, now: now).isTemplate, "Combined badge preserves weekly color without a banked warning")
        let orangeWeekly = weeklyWindow(remaining: 60, days: 2)
        let yellowBanked = ResetCredits(availableCount: 1, credits: [
            .init(id: "yellow", expiresAt: now.addingTimeInterval(5 * 86_400))
        ])
        // Inspect the rendered output so a shared-color regression cannot pass.
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            var hasOrange = false
            var hasYellow = false
            NSAppearance(named: appearanceName)!.performAsCurrentDrawingAppearance {
                let image = QuotaBadge.combinedImage(window: orangeWeekly, credits: yellowBanked, now: now)
                let enlarged = NSImage(size: NSSize(width: image.size.width * 4, height: image.size.height * 4), flipped: false) { bounds in
                    image.draw(in: bounds)
                    return true
                }
                let bitmap = NSBitmapImageRep(data: enlarged.tiffRepresentation!)!
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                              color.alphaComponent > 0.5 else { continue }
                        func matches(_ urgency: QuotaBadge.Urgency) -> Bool {
                            let expected = urgency.color.usingColorSpace(.sRGB)!
                            // Rasterization can change brightness through color profiles.
                            return color.saturationComponent > 0.7 && color.brightnessComponent > 0.2 &&
                                abs(color.hueComponent - expected.hueComponent) < 0.02
                        }
                        hasOrange = hasOrange || matches(.orange)
                        hasYellow = hasYellow || matches(.yellow)
                    }
                }
            }
            try require(hasOrange && hasYellow, "Combined badge renders independent weekly and banked colors in \(appearanceName)")
        }
        try require(!QuotaBadge.combinedImage(window: neutralWeekly, credits: credits, now: now).isTemplate,
                    "Banked warnings remain visible with a neutral weekly quota")
        print("PASS: weekly thresholds and independent combined colors work in light and dark appearances")

        let fiveHourCases: [(Int, Double?, QuotaBadge.Urgency?)] = [
            (80, 3, nil), (80, 2, .orange), (80, 1, .red),
            (40, 3, nil), (40, 2, nil), (40, 1, .orange),
            (10, 3, nil), (10, 2, nil), (10, 1, nil), (10, 1 / 60.0, nil),
            (0, 1 / 60.0, nil), (11, 1 / 60.0, .red),
            (27, 1, nil), (28, 1, .yellow), (34, 1, .yellow),
            (35, 1, .orange), (55, 1, .orange), (56, 1, .red),
            (100, 3.5, .yellow), (100, 4, nil), (40, 0.5, .red),
            (80, 0, nil), (80, -1, nil), (80, nil, nil)
        ]
        for (remaining, hours, expected) in fiveHourCases {
            let window = QuotaWindow(id: "test.primary", title: "5-hour", usedPercent: Double(100 - remaining),
                                     resetsAt: hours.map { now.addingTimeInterval($0 * 3_600) }, windowDurationMins: 300)
            try require(QuotaBadge.fiveHourUrgency(window: window, now: now) == expected,
                        "5-hour urgency with \(remaining)% and \(String(describing: hours)) hours left")
            try require(QuotaBadge.image(window: window, period: .fiveHour, now: now).isTemplate == (expected == nil),
                        "5-hour badge preserves warning colors and native tinting")
        }
        try require(QuotaBadge.fiveHourUrgency(window: nil, now: now) == nil, "Unknown 5-hour quota has no warning")
        print("PASS: 5-hour colors scale weekly thresholds and honor the low-quota exemption and missing reset dates")

        let coloredBadges = [
            QuotaBadge.image(window: weekly, period: .weekly, now: now),
            QuotaBadge.image(window: weekly, period: .fiveHour, now: now),
            QuotaBadge.combinedImage(window: weekly, credits: credits, now: now),
            QuotaBadge.resetExpirationImage(credits: credits, now: now)
        ]
        for colored in coloredBadges {
            let monochrome = QuotaBadge.styled(colored, style: .monochrome)
            try require(monochrome.isTemplate && !colored.isTemplate, "Monochrome removes tint without mutating the colored badge")
            try require(monochrome.size == colored.size && monochrome.accessibilityDescription == colored.accessibilityDescription,
                        "Style preserves badge layout and accessibility text")
            try require(QuotaBadge.styled(colored, style: .fullColor) === colored, "Full color retains warning colors")
        }
        print("PASS: monochrome removes warning tint from all four panels while full color preserves it")

        guard let delegate = NSApp.delegate as? AppDelegate else {
            throw NSError(domain: "MenuBarSettingsCheck", code: 2)
        }
        // Debug checks skip normal app startup, which installs the main menu.
        // Give the previews the same public menu-bar metrics as a normal launch.
        let originalMainMenu = NSApp.mainMenu
        if originalMainMenu == nil { NSApp.mainMenu = NSMenu(title: "Menu Bar Preview Check") }
        defer { NSApp.mainMenu = originalMainMenu }
        let nativePreviewItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(nativePreviewItem) }
        nativePreviewItem.button?.image = combined
        delegate.showSettings()
        guard let window = NSApp.windows.first(where: { $0.title == "Use Your Tokens Settings" }) else {
            throw NSError(domain: "MenuBarSettingsCheck", code: 3)
        }
        func previewImages(in view: NSView) -> [NSImageView] {
            if let image = view as? NSImageView, image.identifier?.rawValue == "menu-bar-preview-image" {
                return [image]
            }
            return view.subviews.flatMap { previewImages(in: $0) }
        }
        try await waitUntil({ previewImages(in: window.contentView!).count == 6 },
                            message: "All item and style previews did not appear")
        try await waitUntil({ nativePreviewItem.button?.window?.frame.height == NSApp.mainMenu?.menuBarHeight },
                            message: "Native status item did not finish layout")
        window.contentView?.layoutSubtreeIfNeeded()
        let nativeButton = nativePreviewItem.button!
        let nativeImageRect = nativeButton.convert(nativeButton.cell!.imageRect(forBounds: nativeButton.bounds), to: nil)
        let nativeHeight = nativeButton.window!.frame.height
        for preview in previewImages(in: window.contentView!) {
            let strip = preview.superview!
            try require(preview.imageScaling == .scaleNone && preview.frame.size == preview.image!.size,
                        "Settings preview displays the exact badge image at native size")
            try require(abs(strip.bounds.height - nativeHeight) < 0.01 &&
                        abs(preview.frame.minY - nativeImageRect.minY) < 0.01 &&
                        abs(strip.bounds.height - preview.frame.maxY - (nativeHeight - nativeImageRect.maxY)) < 0.01,
                        "Settings preview matches native padding: strip \(strip.bounds), image \(preview.frame), native height \(nativeHeight), native image \(nativeImageRect)")
        }
        print("PASS: all six Settings previews match native image size and menu bar vertical padding")
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
        try require(NSApp.windows.filter { $0.title == "Use Your Tokens Settings" }.count == 1, "Settings reuses its window")
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
        try await waitUntil({ secret.isVisible }, message: "Secret Window did not open")
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
        let reopenedSession = delegate.model.simulation
        delegate.model.simulation?.weeklyRemainingPercent = 23
        secret.resignKey()
        delegate.showSettings()
        secret.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try require(delegate.model.simulation === reopenedSession && delegate.model.simulation?.weeklyRemainingPercent == 23,
                    "Leaving Secret Window preserves the editing session and controls")
        NSApp.deactivate()
        try await Task.sleep(for: .milliseconds(100))
        try require(delegate.model.simulation === reopenedSession &&
                    delegate.model.weeklyMenuBarImage.accessibilityDescription?.contains("23% remaining") == true,
                    "Switching apps preserves simulated menu bar values")
        secret.makeKeyAndOrderFront(nil)
        try require(delegate.model.simulation === reopenedSession, "Returning reuses the same simulation")
        secret.close()
        try require(delegate.model.simulation == nil, "Closing after focus loss ends simulation")
        window.close()
        print("PASS: secret window opens once and reopens after closing")
        print("PASS: simulation survives window and app focus loss and resets only on close")
        for _ in 0..<3 {
            delegate.showSecretWindow()
            try await waitUntil({ secret.isVisible }, message: "Secret Window did not open")
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
