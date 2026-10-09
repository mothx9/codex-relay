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
Fleet uses Codex's `parentThreadId`, agent role and nickname when a thread is a
subagent. Its row and session header identify the parent session while the child
remains a separate, openable chat; this relationship travels in the existing
session snapshot and needs no second connection.
Its final heartbeat scrolls with the messages. The floating composer reserves a
measured bottom content inset and has no opaque full-width footer.
The single-line capsule is 38 points high inside 44-point touch targets; scalable
16-point input text and a bounded heartbeat gap keep the footer compact as drafts grow.
Stable item and request-incarnation identities prevent reconstruction on each
snapshot. Markdown parsing is coalesced without waiting for completion; output
updates do not animate every token. Reduce Motion disables state movement.

The system accent is separate from semantic status: **green identifies Working**
in Fleet; the compact session heartbeat uses a neutral text sweep. Orange identifies
Needs You, and failures use red plus text.
Liquid Glass is navigation/composer chrome; prose remains on the content canvas.

No background socket service or transcript persistence is added. Foreground
rehydrates from Hub/Codex. A Follow-up already queued in Codex survives application
termination without local resend.

Pulling down in Fleet requests the current Hub snapshot on the existing operator
socket and reloads recent machine catalogue metadata. Pulling down in a chat
re-reads its first canonical history page; the merge retains live activity and
the scroll position. An explicit Connect thread attempt reports its own status
beside the composer, without a message-send alert. Codex may refuse connection
when another client holds the thread's active writer; history stays readable.

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

For a reproducible recording (requires `ffmpeg` and `ffprobe`):

```sh
python3 scripts/native-walkthrough.py --simulator "$SIMULATOR_UDID"
```

Use the same `--watcher-pid` option when necessary. The walkthrough navigates
Fleet, a failed turn, command output, aggregate activity, a tool result, file
diff, attachments, Needs You, Machines, Diagnostics and Settings. Named test
markers trim launcher frames before MP4/GIF export. Chapter metadata and 15
screens from that same run are saved beside the recording and in
`docs/assets/app/screenshots/flow-*.png`. Review the full recording and each
frame before committing; never publish the raw capture.

Review every exported image before committing. Source fixtures live in
`ProductFixtures`; do not publish screenshots from real project work. The pipeline
covers Fleet, conversation, Needs You, inline question, Terminal, tools, diff,
Machines, Account, Settings, global and machine Diagnostics, the Relay menu,
pairing, live-question conversation/Inbox, notification readiness and context
compaction.

The native icon source is `docs/assets/app/codex-app-icon.svg`; see
[asset attribution](../assets/app/README.md). Other Relay product assets use
`docs/assets/app/mark.svg`. Run
`python3 scripts/branding.py` with librsvg installed to regenerate AppIcon,
PWA icons, the in-app mark and social preview. Check the icon on Home Screen,
not only at full source resolution.

See [localization](localization.md), [test isolation](test-isolation.md) and
[testing](testing.md) for resource generation and safe real-Hub acceptance.

The [navigation rationale](../architecture/native-navigation.md) describes entity
homes. `LiveQuestions` is a bounded presentation hint fed only by accepted live
activity events; history never creates hints or canonical pending requests.

Architecture SVG canvases are transparent, with light/dark foreground styles.
Regenerate them with `python3 scripts/diagrams.py`; retain the source script with
the exports. Native AppIcon has the opaque canvas required by iOS.
