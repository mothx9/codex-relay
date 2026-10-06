# Continue development on macOS

Repository: https://github.com/mothx9/codex-relay, branch main. Work on the existing checkout; do not recreate it. Read README, ARCHITECTURE, DEPLOYMENT, DISCOVERY, VALIDATION, SECURITY and native/README before changing code.

The owner has requested a native SwiftUI iPhone client, short one-time pairing, device management, and moving all development to macOS. The complete operational prompt is transferred privately to the owner's Mac at `~/.cache/codex-relay-wave/HANDOFF_MACOS.md`. It is intentionally not included in the public repository.

Implementation checkpoint: `cfc2c9f` adds device pairing/revocation and native push backend; `02a2a83` adds the SwiftUI client and native CI. Use current main HEAD, including subsequent test/documentation commits.

**New source code is not a production deployment.** The repository prepares rc.4; the installed deployment still uses rc.3. No rc.4 tag/release has been created. The installer defaults to the last published release. Deploy a verified build through the existing persistent service, preserving metadata and credentials, before testing new pairing/device endpoints. Do not start a second production Hub.

```sh
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
GOTOOLCHAIN=go1.27.1 make check build cross
swift test --package-path native
xcodebuild -project native/CodexRelay.xcodeproj -scheme CodexRelay \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/relay-ios-build CODE_SIGNING_ALLOWED=NO build
open native/CodexRelay.xcodeproj
```

Go/race/control tests, three cross builds, five Swift tests, an actual Xcode simulator build and implementation CI pass. Native pairing/control E2E, physical device signing/install and APNs receipt/tap remain unverified. Permission/MCP native forms remain incomplete. The full backend also passed `make check build cross` on macOS with the stable Go 1.27.1 toolchain.

Continue with safe deployment, real OTP/Keychain/revocation checks, isolated native control E2E, complete request forms, owner-provided Apple signing/APNs configuration, then actual physical notification acceptance. Preserve New Turn/Follow-up/Answer/explicit Steer semantics and bounded ephemeral state. Do not equate command ACK with turn completion or fake push tests with actual delivery.

Do not modify network settings or unrelated Codex workloads. Keep credentials, account identifiers, private network details and runtime data outside Git. Retain RC status until the actual acceptance flow passes. This wave was closed by the owner to move development, not because the native client was already fully accepted.
