import SwiftUI
#if canImport(UIKit)
import UIKit
import UserNotifications
#endif

@main struct CodexRelayApp: App {
    @State private var relay: RelayController
    @Environment(\.scenePhase) private var phase
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notifications
    #endif
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-chat") {
            _relay = State(initialValue: PreviewData.conversation(long: ProcessInfo.processInfo.arguments.contains("--long-transcript")))
            return
        }
        #endif
        _relay = State(initialValue: RelayController())
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(relay)
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
