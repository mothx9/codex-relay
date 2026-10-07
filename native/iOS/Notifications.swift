#if canImport(UIKit)
import UIKit
import UserNotifications
import Foundation
import SwiftUI

@MainActor final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // UIKit may deliver these before SwiftUI installs the callbacks.
    private var pendingToken: String?
    private var pendingOpen: RelayDestination?
    private var pendingError: String?
    var onToken: ((String) -> Void)? { didSet { if let pendingToken, let onToken { self.pendingToken = nil; onToken(pendingToken) } } }
    var onOpen: ((RelayDestination) -> Void)? { didSet { if let pendingOpen, let onOpen { self.pendingOpen = nil; onOpen(pendingOpen) } } }
    var onPresent: ((String, String, String?) -> Bool)?
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
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        let key = info["notice_key"] as? String ?? notification.request.identifier
        let kind = info["kind"] as? String ?? ""
        let session = info["session_id"] as? String
        let show = await MainActor.run { self.onPresent?(key, kind, session) ?? true }
        return show ? [.banner, .sound] : []
    }
}

extension RelayController {
    private var pushPreference: String? { credential.map { "relay.pushEnabled." + $0.id } }
    private var permitsNotificationIO: Bool {
        #if DEBUG
        return !previewOnly || ProcessInfo.processInfo.arguments.contains("--notification-acceptance")
        #else
        return !previewOnly
        #endif
    }
    private var wantsPush: Bool { previewOnly ? notificationsEnabled : pushPreference.map { UserDefaults.standard.bool(forKey: $0) } ?? false }
    var notificationReadiness: NotificationReadiness {
        var state = NotificationReadiness()
        state.enabled = notificationsEnabled; state.permission = notificationAllowed; state.connected = online
        state.appleRegistered = apnsToken != nil; state.hubConfigured = nativePushAvailable
        state.relayRegistered = pushRegistered; state.registrationVerified = pushRegistrationVerifiedAt != nil
        return state
    }
    func refreshNotificationPermission() async {
        guard permitsNotificationIO else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAllowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        notificationsEnabled = wantsPush
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
        guard permitsNotificationIO else { return }
        await refreshNotificationPermission()
        guard let api, let identity = credential?.id else { return }
        do {
            let state: NativePushState = try await api.fetch("api/native-push/status")
            guard credential?.id == identity else { return }
            nativePushAvailable = state.configured; pushRegistered = state.registered; pushRegistrationVerifiedAt = Date()
            if state.registered, let key = pushPreference, UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(true, forKey: key); notificationsEnabled = true }
            settingsErrors["notifications"] = nil
            if wantsPush {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                guard credential?.id == identity else { return }
                if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) { UIApplication.shared.registerForRemoteNotifications() }
            }
        } catch { if credential?.id == identity { settingsErrors["notifications"] = error.localizedDescription } }
    }
    func enableNativePush() async {
        guard permitsNotificationIO, settingsProgress["notifications"] == nil else { return }
        settingsProgress["notifications"] = String(localized: "Requesting permission…", bundle: relayLocalizationBundle); settingsErrors["notifications"] = nil
        defer { settingsProgress["notifications"] = nil }
        do {
            let accepted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            settingsProgress["notifications"] = nil
            await refreshNotificationPermission()
            guard accepted else { notificationStatus = String(localized: "Notifications are denied. You can enable them in iOS Settings.", bundle: relayLocalizationBundle); return }
            if !previewOnly, let key = pushPreference { UserDefaults.standard.set(true, forKey: key) }
            notificationsEnabled = true
            notificationStatus = String(localized: "Local alerts enabled while Relay is connected. Remote push setup is separate.", bundle: relayLocalizationBundle)
            if !previewOnly { UIApplication.shared.registerForRemoteNotifications() }
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
        if let key = pushPreference { UserDefaults.standard.set(false, forKey: key) }
        notificationsEnabled = false
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
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
    func noticeIsCurrent(_ notice: SemanticNotice) -> Bool {
        switch notice.kind {
        case .request: return notice.requestID.map { requests[$0] != nil } ?? false
        case .liveQuestion: return liveQuestions.records.contains { $0.id == notice.key }
        case .offline: return online && machines[notice.machineID]?.status == "OFFLINE"
        default: return true
        }
    }
    func deliverLocalNotice(_ notice: SemanticNotice) {
        guard permitsNotificationIO, noticeIsCurrent(notice), localNoticePolicy.admit(notice, readiness: notificationReadiness, selectedSession: selected) else { return }
        let identity = credential?.id
        Task {
            guard credential?.id == identity, notificationReadiness.localReady, !notificationReadiness.remoteOwnsDelivery, noticeIsCurrent(notice) else { return }
            let content = UNMutableNotificationContent()
            content.title = notice.title; content.body = notice.body; content.sound = .default
            content.badge = NSNumber(value: attentionCount)
            var info: [String: String] = ["notice_key": notice.key, "kind": notice.kind.rawValue]
            if !notice.sessionID.isEmpty { info["session_id"] = notice.sessionID }
            if !notice.machineID.isEmpty { info["machine_id"] = notice.machineID }
            if let request = notice.requestID { info["request_id"] = request }
            content.userInfo = info
            do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notice.key, content: content, trigger: nil)) }
            catch { settingsErrors["localAlerts"] = error.localizedDescription }
        }
    }
    func presentNotification(key: String, kind: String, session: String?) -> Bool {
        guard notificationsEnabled, !presentedNotices.contains(key) else { return false }
        presentedNotices.append(key); if presentedNotices.count > 512 { presentedNotices.removeFirst(presentedNotices.count - 512) }
        updateNotificationBadge()
        if kind == "live_question", !liveQuestions.records.contains(where: { $0.id == key }) { return false }
        if kind == "request", online, !requests.values.contains(where: { $0.sessionId == session }) { return false }
        return kind != "turn_completed" || session != selected
    }
    func testLocalNotification() {
        deliverLocalNotice(SemanticNotice(key: "test/" + UUID().uuidString, kind: .test))
    }
    func cancelOfflineNotices() {
        for task in offlineNoticeTasks.values { task.cancel() }; offlineNoticeTasks.removeAll()
    }
    func observeOfflineMachines(previous: [String: Machine]) {
        for machine in machines.values {
            guard machine.status == "OFFLINE" else { offlineNoticeTasks.removeValue(forKey: machine.id)?.cancel(); continue }
            guard previous[machine.id]?.status != nil, previous[machine.id]?.status != "OFFLINE", offlineNoticeTasks[machine.id] == nil else { continue }
            let id = machine.id, seen = machine.lastSeen
            offlineNoticeTasks[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self, self.online, self.machines[id]?.status == "OFFLINE", self.machines[id]?.lastSeen == seen else { return }
                self.deliverLocalNotice(SemanticNotice(key: "offline/" + id + "/" + seen, kind: .offline, machineID: id))
                self.offlineNoticeTasks[id] = nil
            }
        }
    }
    func updateNotificationBadge() {
        guard permitsNotificationIO else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            try? await center.setBadgeCount(credential == nil || !notificationsEnabled ? 0 : attentionCount)
            let delivered = await center.deliveredNotifications()
            let pending = await center.pendingNotificationRequests()
            @MainActor func obsolete(_ info: [AnyHashable: Any]) -> Bool {
                switch info["kind"] as? String {
                case "live_question": return !liveQuestions.records.contains { $0.id == info["notice_key"] as? String }
                case "request":
                    guard online else { return false }
                    if let id = info["request_id"] as? String { return requests[id] == nil }
                    return !requests.values.contains { $0.sessionId == info["session_id"] as? String }
                default: return false
                }
            }
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter { obsolete($0.request.content.userInfo) }.map { $0.request.identifier })
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { obsolete($0.content.userInfo) }.map(\.identifier))
        }
    }
}
#endif

#if DEBUG
/// Isolated OS-notification acceptance. No Hub, pairing or Keychain access.
struct NotificationAcceptanceView: View {
    @Environment(RelayController.self) private var relay
    var body: some View {
        NavigationStack {
            List {
                Button("Allow notifications") { Task { await relay.enableNativePush() } }
                ForEach([SemanticNotice.Kind.completed, .request, .liveQuestion, .failed], id: \.rawValue) { kind in
                    Button(kind.rawValue) { emit(kind) }.accessibilityIdentifier("notice." + kind.rawValue)
                }
                Button("Disable alerts") { relay.notificationsEnabled = false }
                Button("Clear attention") { relay.requests = [:]; relay.liveQuestions.reset(); relay.updateNotificationBadge() }
                Text("Attention: \(relay.attentionCount)").accessibilityIdentifier("notice.count")
                Text(relay.notificationReadiness.localReady ? "Local alerts ready" : "Local alerts off")
                Text("Remote setup required")
            }.navigationTitle("Notification acceptance")
        }.onAppear { relay.online = true }.task { await relay.refreshNotificationPermission() }
    }
    private func emit(_ kind: SemanticNotice.Kind) {
        let key = "acceptance/" + kind.rawValue
        if kind == .request {
            let request = try! RelayJSON.decoder().decode(PendingRequest.self, from: Data(#"{"request_id":"acceptance-request","session_id":"test~thread","machine_id":"test","kind":"user_input","description":"Scope?","expires_at":"2099-01-01T00:00:00Z","can_approve":true}"#.utf8))
            relay.requests[request.id] = request
        }
        if kind == .liveQuestion {
            let event = try! RelayJSON.decoder().decode(RelayEvent.self, from: Data(#"{"kind":"live_question","session_id":"test~thread","machine_id":"test","turn_id":"turn","activity":{"id":"question","kind":"agentMessage","text":"Scope?","questions":[{"title":"Scope?"}]}}"#.utf8))
            relay.liveQuestions.observe(event, activeTurn: "turn", current: true)
            relay.deliverLocalNotice(SemanticNotice.event(event)!)
        } else {
            relay.deliverLocalNotice(SemanticNotice(key: key, kind: kind, sessionID: "test~thread", machineID: "test", requestID: kind == .request ? "acceptance-request" : nil))
        }
        relay.updateNotificationBadge()
    }
}
#endif
