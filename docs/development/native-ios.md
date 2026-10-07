# Native iOS development

Open `native/CodexRelay.xcodeproj`, scheme `CodexRelay`. The application supports
iOS 17+, with Liquid Glass on supported systems and a material fallback.
Use an installed iPhone 16 simulator for reference layout checks.

```sh
swift test --package-path native
xcodebuild -project native/CodexRelay.xcodeproj -scheme CodexRelay \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/relay-ios-build CODE_SIGNING_ALLOWED=NO build-for-testing
```

That command proves compilation, not a paired runtime. A running simulator needs
ad hoc signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`) for Keychain
access. Physical installation needs your Apple signing team and provisioning.
Keep overrides in ignored `native/LocalSigning.xcconfig`, included by
`Signing.xcconfig`; never commit team IDs, profiles or private keys.

## State and presentation

`RelayController` holds canonical machines/sessions/requests and bounded ephemeral
chat/outbox. `SessionTranscript` observes chat independently from the composer.
Stable item and request-incarnation identities prevent reconstruction on each
snapshot. Markdown parsing is coalesced without waiting for completion; output
updates do not animate every token. Reduce Motion disables state movement.

The system accent is separate from semantic status: **green identifies Working**
and its motion, orange identifies Needs You, and failures use red plus text.
Liquid Glass is navigation/composer chrome; prose remains on the content canvas.

No background socket service or transcript persistence is added. Foreground
rehydrates from Hub/Codex. A Follow-up already queued in Codex survives application
termination without local resend.

## Previews and public screenshots

SwiftUI previews and DEBUG launch modes instantiate a controller with Keychain,
network, pairing and notification side effects disabled. They use the actual
production views and fictional `.invalid` account/origin data. Release builds
exclude these entry points. This isolation is for visual review and public
assets; it is not live acceptance evidence.

```sh
python3 scripts/native-screenshots.py --simulator "$SIMULATOR_UDID"
```

The script builds, runs the dedicated screenshot test, exports only its named
attachments to `docs/assets/app/screenshots`, and restores the status bar.
If a development watcher already exists, pass its PID using `--watcher-pid`;
the script suspends and resumes that process. Do not create a duplicate watcher.
Normal launch afterward restores the paired app without clearing Keychain.

Review every exported image before committing. Source fixtures live in
`ProductFixtures`; do not publish screenshots from real project work. The pipeline
covers Fleet, conversation, Needs You, inline question, Terminal, tools, diff,
Machines, Account, Settings, global and machine Diagnostics, the Relay menu, pairing and a live transient assistant question.

The shared vector mark is `docs/assets/app/mark.svg`. Run
`python3 scripts/branding.py` with librsvg installed to regenerate AppIcon,
PWA icons, the in-app mark and social preview. Check the icon on Home Screen,
not only at full source resolution.

See [localization](localization.md), [test isolation](test-isolation.md) and
[testing](testing.md) for resource generation and safe real-Hub acceptance.

The [navigation rationale](../architecture/native-navigation.md) describes entity
homes. `LiveQuestions` is a bounded presentation hint fed only by accepted live
activity events; history never creates hints or canonical pending requests.
