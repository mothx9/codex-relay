# Continue development on macOS

Repository: https://github.com/mothx9/codex-relay, branch main. Work on the existing checkout; do not recreate it. Read README, ARCHITECTURE, DEPLOYMENT, DISCOVERY, VALIDATION, SECURITY and native/README before changing code.

The owner has requested a native SwiftUI iPhone client, short one-time pairing, device management, and moving all development to macOS. The complete operational prompt is transferred privately to the owner's Mac at `~/.cache/codex-relay-wave/HANDOFF_MACOS.md`. It is intentionally not included in the public repository.

Implementation checkpoint: `cfc2c9f` adds device pairing/revocation and native push backend; `02a2a83` adds the SwiftUI client and native CI. Use current main HEAD, including subsequent test/documentation commits.

The macOS continuation upgraded the existing Hub to rc.4 and then upgraded Exon and MacBook agents separately, preserving DB, bootstrap, VAPID and installed credentials. Spark was already offline and remains pending. No rc.4 tag/release has been created; the installer still defaults to the last published release, so use a verified `--binary` for rc.4. Do not start a second production Hub. See the latest [validation checkpoint](VALIDATION.md) for current evidence; earlier three-host PWA results do not prove current Spark reachability or native controls.

```sh
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
GOTOOLCHAIN=go1.27.1 make check build cross
swift test --package-path native
xcodebuild -project native/CodexRelay.xcodeproj -scheme CodexRelay \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/relay-ios-build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
open native/CodexRelay.xcodeproj
```

Go/race/control tests, three cross builds, nine Swift core tests and actual simulator builds pass. Live simulator pairing, Fleet, Keychain restart, isolated New Turn/canonical reply, no optimistic duplicate and foreground reconnect pass. The physical app is signed, installed, trusted and paired on the owner's iPhone. Permission/MCP native forms are implemented; live approval and remaining native controls still need acceptance. Real APNs receipt/tap remains pending. The backend passed `make check build cross` on macOS with stable Go 1.27.1.

Continue with Spark recovery when the owner reports it online, remaining isolated native control/recovery tests, live permission/MCP acceptance, and owner-provided push-capable Apple team/APNs configuration. The owner's Personal Team permits the current physical install but does not supply APNs. Preserve New Turn/Follow-up/Answer/explicit Steer semantics and bounded ephemeral state. Do not equate command ACK with turn completion or fake push tests with actual delivery.

Do not modify network settings or unrelated Codex workloads. Keep credentials, account identifiers, private network details and runtime data outside Git. Retain RC status until the actual acceptance flow passes. This wave was closed by the owner to move development, not because the native client was already fully accepted.
