# Download and install

[Download v0.1.0](https://github.com/mothx9/codex-relay/releases/tag/v0.1.0).
You do not need to clone the repository, install Go or open Xcode to use the
release packages. A Hub with your own HTTPS address and an already signed-in
Codex runtime on each machine are the prerequisites.

## Hub and machines

Download the installer once on each host:

```sh
curl -fL https://github.com/mothx9/codex-relay/releases/download/v0.1.0/install.sh -o install.sh
```

Set `RELAY_HUB_URL` to your real HTTPS origin. On the always-on Hub host:

```sh
sh install.sh hub --public-url "$RELAY_HUB_URL"
```

Create the phone's one-time code on that host:

```sh
~/.local/bin/codex-relay pair --hub-url "$RELAY_HUB_URL" \
  --data-dir "$HOME/.local/share/codex-relay/hub" --name iPhone
```

On each Codex-running machine, create an Agent code from **Relay → Machines →
Add a machine**, then run:

```sh
sh install.sh agent --hub-url "$RELAY_HUB_URL" --pair
```

Enter the eight-digit code at the prompt. The machine ID defaults to its hostname;
use `--machine NAME` for duplicate hostnames or a chosen identifier. The installer
selects the platform, checks the downloaded archive's SHA-256 and installs the
per-user service. Codes expire in five minutes. Existing enrollment is preserved:
upgrades use the existing `--token-file`, rather than `--pair`.

| Host | Package |
| --- | --- |
| Linux x86-64 | `codex-relay-0.1.0-linux-amd64.tar.gz` |
| Linux ARM64 | `codex-relay-0.1.0-linux-arm64.tar.gz` |
| macOS Apple silicon | `codex-relay-0.1.0-darwin-arm64.tar.gz` |

Each archive contains `codex-relay`, `install.sh`, `LICENSE` and this guide.
For offline/manual installation, extract the archive and supply
`sh install.sh … --binary ./codex-relay`. Hub service installation targets Linux;
Agents support the three platforms above. HTTPS and the existing Codex daemon
remain under your control.

## iPhone: choose one route

**Native app, without Xcode:** download
[CodexRelay-0.1.0-ios-unsigned.ipa](https://github.com/mothx9/codex-relay/releases/download/v0.1.0/CodexRelay-0.1.0-ios-unsigned.ipa),
then sign/install it with AltStore Classic on a Mac or Windows computer. Follow
the [iPhone guide](https://github.com/mothx9/codex-relay/blob/v0.1.0/docs/setup/iphone.md).
The IPA is a device build, not a simulator or App Store package. A free Apple
account requires refreshing its signature every seven days. Signing and iOS
Developer Mode are still required; TestFlight is not available for this release.

**Immediate access, without a computer:** open your Hub's HTTPS URL in Safari,
use **Share → Add to Home Screen**, open Relay from its icon and enter the
phone's one-time code. This uses the included web/PWA client. Native photos,
presentation and some controls differ; the [status page](https://github.com/mothx9/codex-relay/blob/v0.1.0/docs/status.md)
explains the supported native features. Home Screen Web Push on supported iOS
does not require your own Apple Developer membership.

Once paired, enter no Apple or OpenAI credentials into Relay. Codex authentication
stays on your machines. Native remote APNs delivery requires separate Apple
capability/provider setup; connected local alerts work independently.

## Verify and upgrade

`SHA256SUMS` covers all downloadable packages, the installer and `release.json`.
The manifest records the exact source commit and artifact sizes/hashes. Download
the checksum file alongside your chosen asset, then verify that entry with
`shasum -a 256` on macOS or `sha256sum` on Linux. A checksum mismatch must stop
installation. The installer verifies its selected archive automatically.

[Upgrade guide](https://github.com/mothx9/codex-relay/blob/v0.1.0/docs/operations/upgrading.md)
· [Troubleshooting](https://github.com/mothx9/codex-relay/blob/v0.1.0/docs/operations/troubleshooting.md)

Developers can clone the repository and use `make build`. Xcode build/signing
instructions live in the development guide, separate from the download path.
