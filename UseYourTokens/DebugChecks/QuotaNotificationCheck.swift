#if DEBUG
import Foundation
import UserNotifications

@MainActor
enum QuotaNotificationCheck {
    static func run() async throws {
        let suite = "UseYourTokens.NotificationCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MenuBarPreferences(defaults: defaults)
        let client = FakeClient()
        let notifications = QuotaNotifications(preferences: preferences, client: client)
        let global = QuotaRefillTracker.Event(id: UUID(), date: .now, titles: ["Weekly"], cause: .unexpected)
        let banked = QuotaRefillTracker.Event(id: UUID(), date: .now, titles: ["Weekly"], cause: .bankedReset)
        let unknown = QuotaRefillTracker.Event(id: UUID(), date: .now, titles: ["Weekly"], cause: .unknown)

        try require(!preferences.notifyAboutGlobalResets && client.requests == 0, "Off by default without permission prompt")
        try require(!notifications.showsPermissionGuidance, "Permission card stays hidden before first enable")
        try require(!notifications.needsSystemSettings, "Pending permission uses the blue prompt card")
        preferences.setNotifyAboutGlobalResets(true)
        client.status = .denied
        await notifications.refreshPermissionStatus()
        try require(notifications.showsPermissionGuidance,
                    "Enabled toggle with disabled system permission shows the card")
        try require(notifications.needsSystemSettings, "Denied permission uses the orange System Settings card")
        preferences.setNotifyAboutGlobalResets(false)
        try require(!notifications.showsPermissionGuidance, "Turning the toggle off hides the denied-permission card")
        client.status = .notDetermined
        await notifications.refreshPermissionStatus()
        await notifications.notifyGlobalResets([global])
        try require(client.sent.isEmpty && client.requests == 0, "Disabled detection neither sends nor prompts")
        client.onRequest = {
            try require(preferences.notifyAboutGlobalResets, "Toggle stays on while permission is pending")
            try require(notifications.showsPermissionGuidance, "Permission card is visible while the first permission prompt is pending")
        }
        await notifications.setEnabled(true)
        client.onRequest = nil
        try require(preferences.notifyAboutGlobalResets && client.requests == 1, "First enable requests permission")
        try require(!notifications.showsPermissionGuidance, "Permission card hides after granting permission")
        try require(MenuBarPreferences(defaults: defaults).notifyAboutGlobalResets, "Enabled preference persists")
        await notifications.notifyGlobalResets([banked, unknown])
        try require(client.sent.isEmpty, "Banked and unknown refills do not notify")
        await notifications.notifyGlobalResets([global])
        try require(client.sent.count == 1 && client.sent[0].0 == "global-reset.\(global.id.uuidString)", "Global reset delivers with stable event ID")
        try require(client.sent[0].1 == "Global quota reset applied" && QuotaNotifications.subtitles.contains(client.sent[0].2), "Requested title and subtitle")
        await notifications.setEnabled(false)
        await notifications.setEnabled(true)
        try require(client.requests == 1, "Re-enabling does not request permission again")
        await notifications.setEnabled(false)
        await notifications.sendTest()
        try require(client.sent.count == 2 && !preferences.notifyAboutGlobalResets, "Test works independently of reset toggle")

        client.status = .denied
        await notifications.setEnabled(true)
        try require(preferences.notifyAboutGlobalResets && notifications.message == nil && client.requests == 1, "Denied permission preserves the enabled preference and uses the card without redundant error text")
        try require(notifications.showsPermissionGuidance, "Permission card remains until permission is granted")
        let restored = QuotaNotifications(preferences: MenuBarPreferences(defaults: defaults), client: client)
        await restored.refreshPermissionStatus()
        try require(restored.showsPermissionGuidance, "Permission card survives relaunch after first enable")
        await notifications.setEnabled(false)
        try require(!notifications.showsPermissionGuidance && notifications.message == nil, "Turning off after enabling hides the card and clears the permission message")
        let disabled = QuotaNotifications(preferences: MenuBarPreferences(defaults: defaults), client: client)
        await disabled.refreshPermissionStatus()
        try require(!disabled.showsPermissionGuidance, "Disabled preference keeps the card hidden across relaunches")
        client.status = .authorized
        await restored.refreshPermissionStatus()
        try require(!restored.showsPermissionGuidance && restored.message == nil, "Permission card hides after granting access in System Settings")
        try require(!restored.needsSystemSettings, "Granted permission clears the System Settings action")
        client.status = .denied
        preferences.setNotifyAboutGlobalResets(true)
        await notifications.notifyGlobalResets([global])
        try require(client.sent.count == 2 && client.requests == 1, "Revoked permission suppresses delivery without prompting")
        await notifications.sendTest()
        try require(client.sent.count == 2 && notifications.message != nil, "Denied test reports permission guidance")

        client.status = .notDetermined
        client.grantsPermission = false
        await notifications.setEnabled(true)
        try require(preferences.notifyAboutGlobalResets && notifications.showsPermissionGuidance,
                    "Denying permission preserves the on toggle and shows guidance")
        try require(notifications.needsSystemSettings && notifications.message == nil,
                    "Returning false from the prompt shows the orange card without an error message")
        client.status = .notDetermined
        client.authorizationError = NSError(domain: UNErrorDomain, code: UNError.Code.notificationsNotAllowed.rawValue)
        await notifications.setEnabled(true)
        try require(preferences.notifyAboutGlobalResets && notifications.showsPermissionGuidance &&
                    notifications.needsSystemSettings && notifications.message == nil,
                    "Throwing notificationsNotAllowed shows the orange card even while the system status still lags")
        client.authorizationError = nil
        client.status = .authorized
        client.failsToSend = true
        await notifications.sendTest()
        try require(notifications.message?.contains("Couldn’t send test notification") == true && !notifications.isSendingTest, "Delivery error is visible and test button recovers")
        print("PASS: notification defaults, persistence, permission flow, reset filtering, content, test delivery, and failures")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "QuotaNotificationCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private final class FakeClient: ResetNotificationClient {
        var status: UNAuthorizationStatus = .notDetermined
        var grantsPermission = true
        var failsToSend = false
        var authorizationError: Error?
        var requests = 0
        var onRequest: (() throws -> Void)?
        var sent: [(String, String, String)] = []

        func authorizationStatus() async -> UNAuthorizationStatus { status }
        func requestAuthorization() async throws -> Bool {
            requests += 1
            try onRequest?()
            if let authorizationError { throw authorizationError }
            status = grantsPermission ? .authorized : .denied
            return grantsPermission
        }
        func send(identifier: String, title: String, subtitle: String) async throws {
            if failsToSend { throw NSError(domain: "TestDelivery", code: 1) }
            sent.append((identifier, title, subtitle))
        }
    }
}
#endif
