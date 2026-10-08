# Release engineering

`VERSION` identifies the release line, currently **0.1.0**. The Go development
default, native marketing version, installer download default and current docs
must agree. Historical validation reports keep their original build identifiers.

## Packages

- `codex-relay-VERSION-linux-amd64.tar.gz`
- `codex-relay-VERSION-linux-arm64.tar.gz`
- `codex-relay-VERSION-darwin-arm64.tar.gz`
- `CodexRelay-VERSION-ios-unsigned.ipa`
- `install.sh`, `release.json`, `SHA256SUMS`

Archives have a flat layout: executable, installer, license and installation
guide. Raw build binaries stay in local `dist/`; they are not separate release
downloads. `release.json` records the source commit and exact asset sizes/hashes;
checksums cover it and the downloadable assets. Packaging excludes stale files
in `dist/`, normalizes tar metadata and validates the unsigned device IPA.

```sh
make package
python3 scripts/native_package.py
python3 scripts/release.py --ipa dist/CodexRelay-0.1.0-ios-unsigned.ipa
```

The IPA is built for arm64 iPhoneOS in Release configuration without personal
signing. Publishing a provisioning profile, certificate, key or development
credential is rejected. End users can sign/sideload the download without Xcode;
the free account's seven-day refresh and separate APNs capability requirements
are explicit in [iPhone installation](../setup/iphone.md). No TestFlight/App Store
availability is implied by packaging an IPA.

## Validation and publication

1. Run `make check`, Swift core tests and the relevant simulator behavioral tests.
2. Rebuild/capture the final sanitized screens and recording; inspect the results.
3. Check the physical development installation where the authorized device and
   signing identity are available. State any unperformed gestures or APNs checks.
4. Commit and run green Go/native CI. Tag that reviewed commit as `vVERSION`.
5. The release workflow checks the tag against `VERSION`, builds the unsigned
   device IPA and host packages, verifies checksums and prepares a draft with
   `docs/releases/vVERSION.md` as its release notes.
6. Download the draft assets, verify checksums, archive contents, manifest commit,
   binary versions on supported hosts and native bundle version/platform.
7. Publish the authorized release. Only then delete explicitly superseded releases
   and tags; do not remove the working download before its replacement exists.

Native remote APNs remains a separately configured integration. Unit/provider
tests and a successful build are not physical delivery proof. A self-hosted
release can ship its supported ordinary controls and connected local alerts
while documenting that external requirement. Apple distribution remains a
separate channel requiring an active team and appropriate configuration.

Keep Hub identity, database, controller/machine enrollment and keys when upgrading.
See [upgrading](../operations/upgrading.md). The installer never restarts Codex.
