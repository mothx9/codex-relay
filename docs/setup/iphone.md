# Install and pair the iPhone client

The current open-source native client is an Xcode development build, not an App
Store download. Open `native/CodexRelay.xcodeproj`, select the `CodexRelay` scheme
and your own signing team, then build/run on an authorized iPhone. Keep personal
signing values in the ignored `native/LocalSigning.xcconfig` if needed; never
commit Apple identifiers, profiles or keys.

Enable Developer Mode and trust the development app when iOS requires it. A
Personal Team can install a development build, but cannot supply the Push
Notifications capability required for real APNs delivery. The rest of Relay
works independently. See [notifications](../architecture/notifications.md).

## First launch

The app explains the three roles: Hub, machine Agents and iPhone controller.
Enter your Hub's exact HTTPS URL and the eight-digit one-time code created on the
Hub host. A code expires after five minutes. Do not enter an admin/bootstrap
token. Failed pairing is shown next to the form; the app does not automatically
retry an uncertain exchange.

Existing paired installs load their credential from Keychain. Ordinary upgrades
do not require re-pairing and must not erase this enrollment.

## Add machines and work

Open **Relay menu → Machines → Add a machine**, generate an Agent code and follow
the Linux/macOS setup guide on that machine. Run Codex normally. Fleet prioritizes
Needs You and current work. A Ready session sends a New Turn; a Working session
normally queues a Follow-up. Steer is a separate current-turn action.

Controllers and Codex accounts are different: controllers authorize access to
Relay; Codex account information comes from the already-authenticated runtime on
your machines. Relay never creates a second OpenAI login.

TestFlight/App Store distribution can be prepared after product acceptance and
Apple configuration. No consumer distribution or real push acceptance is claimed
by a successful simulator build.

<img src="../assets/app/screenshots/pairing.png" width="270" alt="Concise role explanation and one-time iPhone pairing">

See [current distribution and compatibility](../status.md) and
[native notification setup](notifications.md) for the remaining Apple requirements.
