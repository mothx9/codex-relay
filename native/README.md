# Native iPhone client

SwiftUI iOS 17+ client of the same Relay Hub. No embedded Codex runtime, transcript database, browser storage or additional server. It is a new scope explicitly requested after the canonical PWA cutover.

## Build and run

```sh
swift test --package-path native
xcodebuild -project native/CodexRelay.xcodeproj -scheme CodexRelay \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/relay-ios-build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
open native/CodexRelay.xcodeproj
```

Select an installed iPhone simulator and Run, or connect your iPhone and configure your own signing team. Simulator compilation is not proof of physical device installation, account signing or push delivery.

Simulator execution uses ad hoc local signing and simulator-only Keychain entitlements. `CODE_SIGNING_ALLOWED=NO` is sufficient for compilation checks, but the unsigned app cannot pair because iOS Simulator rejects Keychain access. Physical builds use Apple's generated device provisioning profile. Simulator entitlements do not enable APNs.

The target includes `Signing.xcconfig`, which optionally loads the ignored `LocalSigning.xcconfig`. Keep owner-specific `DEVELOPMENT_TEAM` and provisioning overrides in that local file. Never commit Apple account identifiers, team values, certificates or profiles. Xcode may write a team directly into the project when you select it; move that value into the local configuration before committing.

`Views.swift` includes isolated SwiftUI previews for pairing, Fleet, Ready, queued Follow-up, Needs You and device management. Open Xcode's Canvas to render them. Fixtures use fictional `.invalid` addresses. Preview controllers skip Keychain loading, disable Hub transports and pairing, and never request notification consent; they cannot operate the installed Fleet. The normal simulator app remains the client for actual Hub acceptance.

`SessionView.swift` implements the owner's iPhone conversation reference: compact title/host/project header, left-aligned Codex messages, right-aligned user messages and explicit queued Follow-up labels. Native Markdown blocks render headings, bullets, inline formatting and code. Adjacent Terminal/MCP/change activities open selectable detail sheets; their counts describe the available bounded context and do not infer completion from an ACK. The composer stays in a fixed bottom row outside the scrolling transcript, respects the safe area and follows the keyboard, uses [Liquid Glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) on iOS 26+ and a material fallback on older supported iOS versions. Reading older messages suppresses automatic scrolling and offers a return-to-latest button. Steer/Interrupt remain explicit in the session menu, retaining their captured turn identity.

The `Chat · riferimento iPhone` preview and Debug-only `--preview-chat` launch argument use an isolated fixture controller. `--long-transcript` adds enough fictional history for composer/keyboard regression tests. These arguments never load Keychain or connect to the Hub, and are excluded from Release. Normal app launches continue to use the existing paired credential.

On the Hub, deploy the new Go code first: rc.3 does not have the new pairing/device APIs. Mint a code with `codex-relay pair --hub-url "$RELAY_HUB_URL" --data-dir "$HOME/.local/share/codex-relay/hub" --name iPhone`. Enter the real HTTPS origin and 8 digits in the app. Do not paste the bootstrap token. Codes expire in five minutes, are one-use and disappear on Hub restart. The client credential is revocable, expires after 90 days and is stored in Keychain (`AfterFirstUnlockThisDeviceOnly`).

The app uses authenticated WSS for Fleet/status/chat, explicit capabilities for control and a RAM-only bounded outbox. READY submits a New Turn; WORKING submits Follow-up by default; Steer and Interrupt are explicit advanced actions; pending input/command/file approval uses Answer. Disconnect never automatically resends a command. Opening a session fetches bounded Codex history/queue through its agent.

Canonical `agentMessage.questions` now retain their titles and options and appear as question cards, including question-only messages. They are nonblocking conversation context, distinct from a pending `requestUserInput` server RPC. Their presence does not grant Answer or imply that a response is still pending. Native asynchronous-question replies and their resolution state remain unqualified. History starts with 40 raw Codex items and exposes Codex’s continuation cursor for “Carica messaggi precedenti”. The native selected-session window is RAM-only, bounded to 2,048 items / 8 MiB including question context. Live items are reconciled by identity and protected against an older history response. Short background transitions retain this window; a return after five minutes clears and rehydrates it. Closing the session or signing out clears it. The Hub and PWA keep their smaller existing limits. Cursor pagination requires an updated Hub and agent; legacy first-page history remains readable.

Permission requests display the complete requested permissions and grant only for the current turn. MCP forms display the complete schema, provide typed scalar/enum fields, and allow JSON input for nested objects and arrays. Responses are bounded to 64 KiB and validated before sending; arbitrary property names retain their original spelling. Unsupported schema features, including external references and conditional schemas, require local Codex. URL elicitation also stays local. A stale request or offline machine cannot receive an answer.

**Dispositivi** lists machines and operator clients, pauses/resumes agent access, removes/revokes machines, revokes client access and generates pairing codes for additional operators/agents. Codex keeps working locally when Relay access is paused. Account type/email/plan come only from official `account/read`; OpenAI account-wide device/session management stays in ChatGPT Security settings.

## Native notifications

Web Push is for the PWA. The native app uses Apple APNs and requires an Apple developer team with the Push Notifications capability, matching App ID/topic, signing/provisioning and an owner-supplied provider key. Nothing from your Apple account is shipped in this repository.

The normal unsigned simulator build omits signing entitlements. To sign a push-capable Debug build, select the correct team and set `CODE_SIGN_ENTITLEMENTS=iOS/Relay.entitlements`, with `APS_ENVIRONMENT=development` and `INFOPLIST_KEY_RelayAPNSEnvironment=sandbox`. Release uses production for both. Ensure these match the actual provisioning profile. Personal signing without a push entitlement can run the app but cannot prove native APNs delivery.

Create a private Hub JSON config and PKCS8 `.p8` key, both mode 0600. Example **shape only**, replace all identifiers and keep actual values outside Git:

```json
{"team_id":"YOURTEAMID","key_id":"YOURKEY_ID","topic":"your.bundle.identifier","key_file":"AuthKey.p8"}
```

Use the Hub installer with `--apns-config /private/path/apns.json`, a verified rc.4 `--binary`, and a topic matching the signed app bundle ID. It stores a private path record and retains the flag on later installs that omit it. `--apns-config none` explicitly disables the flag without deleting owner keys. Manually configured services require an explicit path before migration so the setting cannot be silently dropped. Restart an already-running Hub after changing its unit, then verify bootstrap reports native push available. The Hub sends outbound HTTPS/HTTP2 to fixed Apple production/sandbox endpoints. Native registrations are tied to paired operator devices; revoke/expiry stops delivery and removal deletes the registration. Unregistered/bad tokens are retired. Privacy is on by default; prompt and command text never appears in push. Notification payloads carry the session identity for direct navigation. No Apple credential goes to an agent.

After deployment and signing, enable notifications from Dispositivi on the physical iPhone. Open a session before sending the test so its tap has a session destination. Actual closed-app receipt and tap must be confirmed physically; mocked provider tests prove request structure/signing, not real delivery.

## Current verification and gaps

Go tests, race tests, nine browser control tests, fourteen Swift core tests, four installer tests and a real Xcode 27 simulator build pass. Live simulator acceptance passed OTP pairing to the existing HTTPS Hub, Fleet from the three production hosts, Keychain recovery after process restart, an isolated New Turn, a fresh Codex reply, one canonical user bubble with no optimistic duplicate, and foreground reconnect. It passed again with the conversation redesign. An isolated UI test covers the fixed composer with long history and keyboard, question cards, tool details and draft retention. The physical app was signed, installed, trusted and opened on the owner's iPhone; the owner also confirmed pairing. The redesigned chat was subsequently signed, installed and launched successfully. Physical control E2E and real APNs receipt/tap remain pending. Native permission/MCP forms compile and schema handling is covered by core tests; live approval acceptance, asynchronous-question replies, Follow-up, Steer/Interrupt and recovery coverage remain pending.

Temporary bootstrap failures retry with backoff; 401/403 retires the local revoked/expired credential and returns to pairing. Retrying Steer retains its original expected turn identity, and Interrupt captures the turn before confirmation. An explicit conversion to Follow-up/New Turn remains a separate user action.

`CodexRelayUITests` includes an isolated chat test and an opt-in live acceptance test. The live case skips without `AcceptanceConfig.json` in the built test bundle. The private configuration supplies `origin`, `code`, `machineIDs`, `sessionID`, `sessionTitle` and `sendTurn`. Use a freshly generated OTP and a dedicated isolated thread, never an unrelated working session. Build for testing with local simulator signing, place the configuration in the built test bundle, then run `test-without-building` with parallel testing disabled on the intended simulator. `-collect-test-diagnostics never` avoids an observed Xcode simulator-diagnostics collection hang after successful tests; test assertions still run. Keep configurations, screenshots and result bundles outside Git. Suspend any rebuild watcher while the test runs and restore it afterwards. CI compiles the test target without private configuration and does not claim a live acceptance run.

There is deliberately no automatic transcript/outbox persistence and no background WebSocket service. Foreground reconnect reconstructs current state from the Hub/Codex. A queued Follow-up remains owned by Codex even if the app is terminated.
