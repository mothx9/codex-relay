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
        if ProcessInfo.processInfo.arguments.contains("--notification-acceptance") || ProcessInfo.processInfo.arguments.contains("--preview-onboarding") || ProcessInfo.processInfo.arguments.contains("--product-screenshot") {
            _relay = State(initialValue: RelayController(preview: true))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-chat") {
            _relay = State(initialValue: PreviewData.conversation(long: ProcessInfo.processInfo.arguments.contains("--long-transcript")))
            return
        }
        #endif
        _relay = State(initialValue: RelayController())
    }
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--notification-acceptance") { NotificationAcceptanceView().environment(relay) }
                else if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--product-screenshot"), index + 1 < ProcessInfo.processInfo.arguments.count {
                    ProductPreviewScreen(surface: ProcessInfo.processInfo.arguments[index + 1])
                } else { RootView().environment(relay) }
                #else
                RootView().environment(relay)
                #endif
            }
                #if canImport(UIKit)
                .onAppear {
                    notifications.onToken = { token in relay.apnsToken = token; relay.appleRegistrationFailed = false; Task { await relay.registerNativePush() } }
                    notifications.onOpen = { target in relay.navigate(target) }
                    notifications.onError = { message in relay.appleRegistrationFailed = true; relay.notificationStatus = message }
                    notifications.onPresent = { key, kind, session in relay.presentNotification(key: key, kind: kind, session: session) }
                }
                #endif
                .onChange(of: phase) { _, value in if value == .background { relay.background() } else if value == .active { relay.foreground() } }
                .onOpenURL { url in
                    if let target = RelayDestination.link(url) { relay.navigate(target) }
                }
        }
    }
}
