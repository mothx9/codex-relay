#if canImport(UIKit)
import UIKit
import UserNotifications
import Foundation

@MainActor final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // UIKit may deliver these before SwiftUI installs the callbacks.
    private var pendingToken: String?
    private var pendingOpen: RelayDestination?
    private var pendingError: String?
    var onToken: ((String) -> Void)? { didSet { if let pendingToken, let onToken { self.pendingToken = nil; onToken(pendingToken) } } }
    var onOpen: ((RelayDestination) -> Void)? { didSet { if let pendingOpen, let onOpen { self.pendingOpen = nil; onOpen(pendingOpen) } } }
    var onError: ((String) -> Void)? { didSet { if let pendingError, let onError { self.pendingError = nil; onError(pendingError) } } }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let value = token.map { String(format: "%02x", $0) }.joined()
        if let onToken { onToken(value) } else { pendingToken = value }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        let message = String(localized: "Apple registration unavailable. Check the signed app’s Push Notifications entitlement and provisioning profile.", bundle: relayLocalizationBundle)
        if let onError { onError(message) } else { pendingError = message }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let payload = response.notification.request.content.userInfo
        guard let target = RelayDestination.notification(session: payload["session_id"] as? String, machine: payload["machine_id"] as? String) else { return }
        await MainActor.run {
            if let onOpen = self.onOpen { onOpen(target) } else { self.pendingOpen = target }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .badge] }
}

extension RelayController {
    private var pushPreference: String? { credential.map { "relay.pushEnabled." + $0.id } }
    private var wantsPush: Bool { pushPreference.map { UserDefaults.standard.bool(forKey: $0) } ?? false }
    func refreshNotificationPermission() async {
        guard !previewOnly else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: notificationPermission = String(localized: "Allowed", bundle: relayLocalizationBundle)
        case .denied: notificationPermission = String(localized: "Denied", bundle: relayLocalizationBundle)
        case .notDetermined: notificationPermission = String(localized: "Not requested", bundle: relayLocalizationBundle)
        case .provisional: notificationPermission = String(localized: "Quiet delivery", bundle: relayLocalizationBundle)
        case .ephemeral: notificationPermission = String(localized: "Temporary", bundle: relayLocalizationBundle)
        @unknown default: notificationPermission = String(localized: "Unavailable", bundle: relayLocalizationBundle)
        }
    }
    func refreshNativePush() async {
        guard !previewOnly else { return }
        await refreshNotificationPermission()
        guard let api, let identity = credential?.id else { return }
        do {
            let state: NativePushState = try await api.fetch("api/native-push/status")
            guard credential?.id == identity else { return }
            nativePushAvailable = state.configured; pushRegistered = state.registered; pushRegistrationVerifiedAt = Date()
            if state.registered, let key = pushPreference, UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(true, forKey: key) }
            settingsErrors["notifications"] = nil
            if wantsPush {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                guard credential?.id == identity else { return }
                if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) { UIApplication.shared.registerForRemoteNotifications() }
            }
        } catch { if credential?.id == identity { settingsErrors["notifications"] = error.localizedDescription } }
    }
    func enableNativePush() async {
        guard !previewOnly, settingsProgress["notifications"] == nil else { return }
        settingsProgress["notifications"] = String(localized: "Requesting permission…", bundle: relayLocalizationBundle); settingsErrors["notifications"] = nil
        defer { settingsProgress["notifications"] = nil }
        do {
            let accepted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshNotificationPermission()
            guard accepted else { notificationStatus = String(localized: "Notifications are denied. You can enable them in iOS Settings.", bundle: relayLocalizationBundle); return }
            if let key = pushPreference { UserDefaults.standard.set(true, forKey: key) }
            notificationStatus = String(localized: "Registering this iPhone with Apple…", bundle: relayLocalizationBundle)
            UIApplication.shared.registerForRemoteNotifications()
        } catch { settingsErrors["notifications"] = error.localizedDescription }
    }
    func registerNativePush() async {
        guard let api, let apnsToken, wantsPush, let identity = credential?.id else { return }
        guard nativePushAvailable else { notificationStatus = String(localized: "iOS permission and Apple registration are independent of the Hub. Configure APNs on the Hub to complete enrollment.", bundle: relayLocalizationBundle); return }
        guard settingsProgress["pushRegistration"] == nil else { return }
        settingsProgress["pushRegistration"] = String(localized: "Registering with Relay…", bundle: relayLocalizationBundle)
        defer { settingsProgress["pushRegistration"] = nil }
        struct Registration: Encodable, Sendable { let token: String; let environment: String; let privacy: Bool }
        let environment = Bundle.main.object(forInfoDictionaryKey: "RelayAPNSEnvironment") as? String ?? "sandbox"
        let privacy = UserDefaults.standard.object(forKey: "relay.pushPrivacy") as? Bool ?? true
        do {
            let _: Ack = try await api.post("api/native-push/subscribe", body: Registration(token: apnsToken, environment: environment, privacy: privacy))
            guard credential?.id == identity else { return }
            pushRegistered = true; pushRegistrationVerifiedAt = Date(); settingsErrors["notifications"] = nil
            notificationStatus = String(localized: "Registered with Relay. Send a test to verify delivery on this iPhone.", bundle: relayLocalizationBundle)
        } catch { if credential?.id == identity { settingsErrors["notifications"] = error.localizedDescription } }
    }
    func disableNativePush() async {
        guard let api, settingsProgress["notifications"] == nil, settingsProgress["pushRegistration"] == nil else { return }
        let identity = credential?.id
        settingsProgress["notifications"] = String(localized: "Disabling notifications…", bundle: relayLocalizationBundle); settingsErrors["notifications"] = nil
        defer { settingsProgress["notifications"] = nil }
        do {
            let _: Ack = try await api.fetch("api/native-push/unsubscribe", body: [:])
            guard credential?.id == identity else { return }
            if let key = pushPreference { UserDefaults.standard.set(false, forKey: key) }
            pushRegistered = false; pushRegistrationVerifiedAt = Date(); notificationStatus = String(localized: "Relay registration removed for this iPhone. iOS permission is unchanged.", bundle: relayLocalizationBundle)
            UIApplication.shared.unregisterForRemoteNotifications()
        } catch { settingsErrors["notifications"] = error.localizedDescription }
    }
    func testNativePush() async {
        guard let api, pushRegistered, settingsProgress["notifications"] == nil else { return }
        settingsProgress["notifications"] = String(localized: "Sending test…", bundle: relayLocalizationBundle); settingsErrors["notifications"] = nil
        defer { settingsProgress["notifications"] = nil }
        struct Queued: Decodable, Sendable { let queued: Bool }
        do { let _: Queued = try await api.fetch("api/push/test", body: ["session_id": selected]); notificationStatus = String(localized: "Test queued. Confirm receipt on this iPhone; queue acceptance is not delivery.", bundle: relayLocalizationBundle) }
        catch { settingsErrors["notifications"] = error.localizedDescription }
    }
    func updateNotificationBadge() {
        guard !previewOnly else { return }
        let count = credential == nil ? 0 : requests.count
        let pendingSessions = Set(requests.values.map(\.sessionId))
        let currentSnapshot = online
        Task {
            let center = UNUserNotificationCenter.current()
            try? await center.setBadgeCount(count)
            guard currentSnapshot else { return }
            let delivered = await center.deliveredNotifications()
            let resolved = delivered.filter {
                let payload = $0.request.content.userInfo
                return payload["kind"] as? String == "request" && (payload["session_id"] as? String).map { !pendingSessions.contains($0) } == true
            }.map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: resolved)
        }
    }
}
#endif
