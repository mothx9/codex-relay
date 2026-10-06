#if canImport(UIKit)
import UIKit
import UserNotifications
import Foundation

@MainActor final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var onToken: ((String) -> Void)?
    var onOpen: ((String) -> Void)?
    var onError: ((String) -> Void)?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { UNUserNotificationCenter.current().delegate = self; return true }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) { onToken?(token.map { String(format: "%02x", $0) }.joined()) }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) { onError?("APNs non disponibile: verifica firma e capability Push Notifications.") }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["session_id"] as? String
        if let id, !id.isEmpty { await MainActor.run { self.onOpen?(id) } }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
extension RelayController {
    func refreshNotificationPermission() async {
        guard !previewOnly else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: notificationPermission = "Consentito"
        case .denied: notificationPermission = "Negato"
        case .notDetermined: notificationPermission = "Non richiesto"
        case .provisional: notificationPermission = "Provvisorio"
        case .ephemeral: notificationPermission = "Temporaneo"
        @unknown default: notificationPermission = "Non disponibile"
        }
    }
    func enableNativePush() async {
        guard !previewOnly else { return }
        do {
            guard nativePushAvailable else { throw HubFailure.message("Configura APNs sul Hub prima di abilitare le notifiche.") }
            let accepted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshNotificationPermission()
            if !accepted { notificationStatus = "Permesso notifiche negato. Puoi abilitarlo nelle Impostazioni iOS."; return }
            notificationStatus = "Registro questo iPhone con Apple…"; UIApplication.shared.registerForRemoteNotifications()
        } catch { self.error = error.localizedDescription }
    }
    func registerNativePush() async {
        guard let api, let apnsToken else { return }
        struct Registration: Encodable, Sendable { let token: String; let environment: String; let privacy: Bool }
        let environment = Bundle.main.object(forInfoDictionaryKey: "RelayAPNSEnvironment") as? String ?? "sandbox"
        let privacy = UserDefaults.standard.object(forKey: "relay.pushPrivacy") as? Bool ?? true
        do { let _: Ack = try await api.post("api/native-push/subscribe", body: Registration(token: apnsToken, environment: environment, privacy: privacy)); pushRegistered = true; notificationStatus = "Notifiche registrate. La ricezione va verificata sull’iPhone." } catch { self.error = error.localizedDescription }
    }
    func disableNativePush() async {
        guard let api else { return }
        do { let _: Ack = try await api.fetch("api/native-push/unsubscribe", body: [:]); pushRegistered = false; notificationStatus = "Notifiche disabilitate per questo dispositivo"; UIApplication.shared.unregisterForRemoteNotifications() } catch { self.error = error.localizedDescription }
    }
    func testNativePush() async {
        guard let api else { return }
        struct Queued: Decodable, Sendable { let queued: Bool }
        do { let _: Queued = try await api.fetch("api/push/test", body: ["session_id":selected]); notificationStatus = "Prova accodata; conferma ricezione sul dispositivo." } catch { self.error = error.localizedDescription }
    }
}
#endif
