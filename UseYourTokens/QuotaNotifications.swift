import Foundation
import AppKit
import Observation
import UserNotifications

@MainActor
protocol ResetNotificationClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func send(identifier: String, title: String, subtitle: String) async throws
}

@MainActor
final class SystemResetNotificationClient: NSObject, ResetNotificationClient, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func send(identifier: String, title: String, subtitle: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@Observable
@MainActor
final class QuotaNotifications {
    private(set) var isRequestingPermission = false
    private(set) var isSendingTest = false
    private(set) var message: String?
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @ObservationIgnored private let preferences: MenuBarPreferences
    @ObservationIgnored private let client: any ResetNotificationClient

    static let subtitles = [
        "Give that idea a go.",
        "The unfinished project awaits.",
        "Happy building.",
        "Your mana is restored.",
        "Tibo sends regards."
    ]

    init(preferences: MenuBarPreferences, client: (any ResetNotificationClient)? = nil) {
        self.preferences = preferences
        self.client = client ?? SystemResetNotificationClient()
    }

    var showsPermissionGuidance: Bool {
        preferences.notifyAboutGlobalResets && authorizationStatus != .authorized
    }

    var needsSystemSettings: Bool { authorizationStatus == .denied }

    func openNotificationSettings() {
        var components = URLComponents(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        if let identifier = Bundle.main.bundleIdentifier {
            components?.queryItems = [URLQueryItem(name: "id", value: identifier)]
        }
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }

    func refreshPermissionStatus() async {
        authorizationStatus = await client.authorizationStatus()
        if authorizationStatus == .authorized { message = nil }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isRequestingPermission, !isSendingTest else { return }
        message = nil
        preferences.setNotifyAboutGlobalResets(enabled)
        guard enabled else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        do {
            _ = try await ensurePermission()
            // The orange card already explains denied permission and opens Settings.
            if needsSystemSettings { message = nil }
        } catch {
            message = "Couldn’t request notification permission: \(error.localizedDescription)"
        }
    }

    func notifyGlobalResets(_ events: [QuotaRefillTracker.Event]) async {
        guard preferences.notifyAboutGlobalResets, events.contains(where: { $0.cause == .unexpected }) else { return }
        // Automatic delivery must never display a permission prompt.
        await refreshPermissionStatus()
        guard authorizationStatus == .authorized else { return }
        for event in events where event.cause == .unexpected {
            guard preferences.notifyAboutGlobalResets else { return }
            do { try await send(identifier: "global-reset.\(event.id.uuidString)") }
            catch { message = "Couldn’t send notification: \(error.localizedDescription)" }
        }
    }

    func sendTest() async {
        guard !isSendingTest, !isRequestingPermission else { return }
        isSendingTest = true
        message = nil
        defer { isSendingTest = false }
        do {
            guard try await ensurePermission() else { return }
            try await send(identifier: "global-reset.test.\(UUID().uuidString)")
        } catch {
            message = "Couldn’t send test notification: \(error.localizedDescription)"
        }
    }

    private func ensurePermission() async throws -> Bool {
        await refreshPermissionStatus()
        if authorizationStatus == .authorized { return true }
        if authorizationStatus == .notDetermined {
            do {
                let granted = try await client.requestAuthorization()
                authorizationStatus = granted ? .authorized : .denied
                if granted { return true }
            } catch {
                // macOS can throw notificationsNotAllowed for “Don’t Allow”
                // instead of returning false. Its settings read may still lag.
                await refreshPermissionStatus()
                let notificationError = error as NSError
                if authorizationStatus == .denied ||
                    (notificationError.domain == UNErrorDomain &&
                     notificationError.code == UNError.Code.notificationsNotAllowed.rawValue) {
                    authorizationStatus = .denied
                } else if authorizationStatus == .authorized {
                    return true
                } else {
                    throw error
                }
            }
        }
        message = "Notifications are disabled. Allow notifications for Use Your Tokens in System Settings → Notifications."
        return false
    }

    private func send(identifier: String) async throws {
        try await client.send(identifier: identifier, title: "Global quota reset applied",
                              subtitle: Self.subtitles.randomElement()!)
    }
}
