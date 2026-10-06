import SwiftUI
#if canImport(UIKit)
import UIKit
import UserNotifications
#endif

@main struct CodexRelayApp: App {
    @StateObject private var relay = RelayController()
    @Environment(\.scenePhase) private var phase
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notifications
    #endif
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(relay).preferredColorScheme(.dark)
                #if canImport(UIKit)
                .onAppear {
                    notifications.onToken = { token in relay.apnsToken = token; Task { await relay.registerNativePush() } }
                    notifications.onOpen = { id in relay.open(id) }
                    notifications.onError = { message in relay.notificationStatus = message }
                }
                #endif
                .onChange(of: phase) { _, value in if value == .background { relay.background() } else if value == .active { relay.foreground() } }
                .onOpenURL { url in
                    guard url.scheme == "codex-relay", url.host == "session" else { return }
                    let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")); if !id.isEmpty { relay.open(id) }
                }
        }
    }
}
