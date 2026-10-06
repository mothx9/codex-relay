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

The target includes `Signing.xcconfig`, which optionally loads the ignored `LocalSigning.xcconfig`. Keep owner-specific `DEVELOPMENT_TEAM` and provisioning overrides in that local file. Never commit Apple account identifiers, team values, certificates or profiles. Xcode may write a team directly into the project when you select it; move that value into the local configuration before committing.

`Views.swift` includes isolated SwiftUI previews for pairing, Fleet, Ready, queued Follow-up, Needs You and device management. Open Xcode's Canvas to render them. Fixtures use fictional `.invalid` addresses. Preview controllers skip Keychain loading, disable Hub transports and pairing, and never request notification consent; they cannot operate the installed Fleet. The normal simulator app remains the client for actual Hub acceptance.

On the Hub, deploy the new Go code first: rc.3 does not have the new pairing/device APIs. Mint a code with `codex-relay pair --hub-url "$RELAY_HUB_URL" --data-dir "$HOME/.local/share/codex-relay/hub" --name iPhone`. Enter the real HTTPS origin and 8 digits in the app. Do not paste the bootstrap token. Codes expire in five minutes, are one-use and disappear on Hub restart. The client credential is revocable, expires after 90 days and is stored in Keychain (`AfterFirstUnlockThisDeviceOnly`).

The app uses authenticated WSS for Fleet/status/chat, explicit capabilities for control and a RAM-only bounded outbox. READY submits a New Turn; WORKING submits Follow-up by default; Steer and Interrupt are explicit advanced actions; pending input/command/file approval uses Answer. Disconnect never automatically resends a command. Opening a session fetches bounded Codex history/queue through its agent.

Permission requests display the complete requested permissions and grant only for the current turn. MCP forms display the complete schema, provide typed scalar/enum fields, and allow JSON input for nested objects and arrays. Responses are bounded to 64 KiB and validated before sending; arbitrary property names retain their original spelling. Unsupported schema features, including external references and conditional schemas, require local Codex. URL elicitation also stays local. A stale request or offline machine cannot receive an answer.

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

Go tests, race tests, nine browser control tests, nine Swift core tests and a real Xcode 27 simulator build pass. Native permission/MCP forms compile and their schema handling is covered by core tests; live native approval acceptance remains pending. A physical-device build signed with the owner's local Personal Team passes signature verification, but installation has not succeeded. Live Hub OTP exchange, one-use rejection, five-minute expiry and immediate device revocation pass independently of the native UI. Native Fleet/chat/Follow-up E2E and real APNs receipt/tap remain unverified. The native project has no app-store packaging.

There is deliberately no automatic transcript/outbox persistence and no background WebSocket service. Foreground reconnect reconstructs current state from the Hub/Codex. A queued Follow-up remains owned by Codex even if the app is terminated.
