# Native iPhone client

SwiftUI controller for the self-hosted Relay Hub. iOS 17 or later; Liquid Glass
on supported systems and material fallback on earlier versions.

- [Build, run, previews and signing](../docs/development/native-ios.md)
- [Install and pair an iPhone](../docs/setup/iphone.md)
- [Tests and live acceptance](../docs/development/testing.md)
- [Localization](../docs/development/localization.md)
- [Notifications and APNs](../docs/architecture/notifications.md)

`RelayCore/` contains transport and presentation models testable with SwiftPM.
`iOS/` contains the SwiftUI application; `iOSUITests/` contains behavioral UI
checks. No Codex runtime or transcript database is embedded in the application.
