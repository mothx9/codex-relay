# Native iPhone client

SwiftUI iOS 17+ client of the same Relay Hub. No embedded Codex runtime, transcript database, browser storage or additional server. It is a new scope explicitly requested after the canonical PWA cutover.

## Build and run

```sh
swift test --package-path native
xcodebuild -project native/CodexRelay.xcodeproj -scheme CodexRelay \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/relay-ios-build CODE_SIGNING_ALLOWED=NO build
open native/CodexRelay.xcodeproj
```

Select an installed iPhone simulator and Run, or connect your iPhone and configure your own signing team. Simulator compilation is not proof of physical device installation, account signing or push delivery.

On the Hub, deploy the new Go code first: rc.3 does not have the new pairing/device APIs. Mint a code with `codex-relay pair --hub-url "$RELAY_HUB_URL" --data-dir "$HOME/.local/share/codex-relay/hub" --name iPhone`. Enter the real HTTPS origin and 8 digits in the app. Do not paste the bootstrap token. Codes expire in five minutes, are one-use and disappear on Hub restart. The client credential is revocable, expires after 90 days and is stored in Keychain (`AfterFirstUnlockThisDeviceOnly`).

The app uses authenticated WSS for Fleet/status/chat, explicit capabilities for control and a RAM-only bounded outbox. READY submits a New Turn; WORKING submits Follow-up by default; Steer and Interrupt are explicit advanced actions; pending input/command/file approval uses Answer. Disconnect never automatically resends a command. Opening a session fetches bounded Codex history/queue through its agent.

**Dispositivi** lists machines and operator clients, pauses/resumes agent access, removes/revokes machines, revokes client access and generates pairing codes for additional operators/agents. Codex keeps working locally when Relay access is paused. Account type/email/plan come only from official `account/read`; OpenAI account-wide device/session management stays in ChatGPT Security settings.

## Native notifications

Web Push is for the PWA. The native app uses Apple APNs and requires an Apple developer team with the Push Notifications capability, matching App ID/topic, signing/provisioning and an owner-supplied provider key. Nothing from your Apple account is shipped in this repository.

The normal unsigned simulator build omits signing entitlements. To sign a push-capable Debug build, select the correct team and set `CODE_SIGN_ENTITLEMENTS=iOS/Relay.entitlements`, with `APS_ENVIRONMENT=development` and `INFOPLIST_KEY_RelayAPNSEnvironment=sandbox`. Release uses production for both. Ensure these match the actual provisioning profile. Personal signing without a push entitlement can run the app but cannot prove native APNs delivery.

Create a private Hub JSON config and PKCS8 `.p8` key, both mode 0600. Example **shape only**, replace all identifiers and keep actual values outside Git:

```json
{"team_id":"YOURTEAMID","key_id":"YOURKEY_ID","topic":"your.bundle.identifier","key_file":"AuthKey.p8"}
```

Pass `--apns-config /private/path/apns.json` to the persistent Hub service, with a topic matching the signed app bundle ID. The installer currently does not configure this flag automatically. The Hub sends outbound HTTPS/HTTP2 to fixed Apple production/sandbox endpoints. Native registrations are tied to paired operator devices; revoke/expiry stops delivery and removal deletes the registration. Unregistered/bad tokens are retired. Privacy is on by default; prompt and command text never appears in push. Notification payloads carry the session identity for direct navigation. No Apple credential goes to an agent.

After deployment and signing, enable notifications from Dispositivi on the physical iPhone. Open a session before sending the test so its tap has a session destination. Actual closed-app receipt and tap must be confirmed physically; mocked provider tests prove request structure/signing, not real delivery.

## Current verification and gaps

Go tests, race tests, nine browser control tests, five Swift core tests and a real Xcode 27 simulator build pass at the handoff checkpoint. Physical app installation, OTP against the newly deployed Hub, native Fleet/chat/Follow-up E2E and real APNs receipt/tap remain unverified. Permission and MCP elicitation approval currently refer the user to the PWA/local Codex for full schema review; command/file approval and structured questions have native forms. The native project has no final visual polish or app-store packaging.

There is deliberately no automatic transcript/outbox persistence and no background WebSocket service. Foreground reconnect reconstructs current state from the Hub/Codex. A queued Follow-up remains owned by Codex even if the app is terminated.
