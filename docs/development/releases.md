# Release engineering

A release requires a reviewed commit, green Go/native CI, coherent version
reporting and verified artifacts. Current productization remains an explicit RC;
a final `v0.1.0` must not be declared complete while required physical native
notification acceptance is unavailable.

## Build artifacts

`make cross VERSION=<candidate-version>` builds Linux amd64, Linux arm64 and
macOS arm64 binaries in `dist/`. The version is embedded with Go linker flags;
verify each executable on its target platform with `codex-relay version`.
The installer selects the matching architecture and verifies `SHA256SUMS` for
release downloads. Candidate source installs use `--binary` until a matching
public release exists. Never imply that locally built artifacts are published.

Release publication must include the exact binaries, SHA-256 checksums, source
commit and compatibility/upgrade notes. Keep Hub identity, SQLite state, keys and
enrollment across upgrades. Read [upgrading](../operations/upgrading.md).

## Acceptance gates

- Formatting, vet, ordinary/race Go, PWA, installer and Swift core checks.
- Simulator build-for-testing and relevant behavioral UI acceptance.
- Safe real-Hub/Agent synchronization and owned-thread control acceptance.
- Signed physical iPhone installation, gestures, lifecycle and app icon review.
- Real APNs banners/Notification Center/badge/tap/cold start where required.
- Privacy review of source, docs, assets, logs and release attachments.

If only Apple capability/provisioning/provider credentials remain unavailable,
retain the RC and name the precise external requirement. Unit tests, simulator
notifications and fake provider responses are not physical APNs proof.

The iOS source tree is prepared for future TestFlight/App Store distribution,
but an Xcode development build is the current installation path. Do not submit
to an Apple distribution channel without owner authorization and configured
signing/capability access. The Hub remains self-hosted in either model.

## Automation

`make checksums VERSION=...` cross-builds all three targets and writes checksums
for that exact artifact set. A pushed version tag runs `.github/workflows/release.yml`:
Swift/native build, backend checks, cross-builds and checksum verification. It
creates a **draft** GitHub release, with prerelease classification for suffixed
versions. It never auto-publishes final acceptance. The owner reviews the actual
physical acceptance and compatibility notes before publishing the draft.

The installer retains its legacy published default for existing manual workflows.
New `--pair` installations must use `--binary` or explicitly select a compatible
published `RELAY_VERSION`; they cannot silently download an older binary lacking
the guided-pairing command. Source build defaults are `0.1.0-rc.5`; an embedded
version string alone does not mean a matching release has been published.
