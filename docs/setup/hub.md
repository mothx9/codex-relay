# Install a Hub

Use an always-on Linux host with an HTTPS origin and WebSocket-capable reverse
proxy. The Hub needs no GPU, Codex login, Node runtime or external database.
Agents connect outbound; never expose a Codex app-server socket to the network.

## Download

No clone or Go installation is required. Download the v0.1.0 installer on the Hub host:

```sh
curl -fL https://github.com/mothx9/codex-relay/releases/download/v0.1.0/install.sh -o install.sh
```

The installer selects the Linux archive and verifies its checksum. For offline
installation, download/extract the matching archive and supply `--binary
./codex-relay`. Developers can still clone/build from source; that is optional.

## Install the service

Set `RELAY_HUB_URL` to your **actual HTTPS origin**, without a path. Configure
HTTPS using your own proxy or direct Hub TLS. Relay does not configure a VPN,
DNS, firewall or Wi-Fi.

```sh
sh install.sh hub --public-url "$RELAY_HUB_URL"
```

The per-user systemd service listens on loopback by default. Private metadata and
credentials live under `~/.local/share/codex-relay/hub`. For operation after
logout, the host administrator can enable user lingering:

```sh
sudo loginctl enable-linger "$(id -un)"
systemctl --user status codex-relay-hub
```

Use `--dry-run` to inspect the service without writing files. `--no-start` on
Linux installs the files without starting/enabling the service. Review
[access boundaries](../architecture/access.md) before exposing the Hub.

## Pair the iPhone

Run on the Hub host, using the same private directory:

```sh
~/.local/bin/codex-relay pair --hub-url "$RELAY_HUB_URL" \
  --data-dir "$HOME/.local/share/codex-relay/hub" --name iPhone
```

Enter the displayed Hub URL and one-time code in Codex Relay. The code expires
after five minutes and can be redeemed once. The bootstrap credential is read
locally by the CLI; do not copy it to the phone, shell arguments, chat or Git.
Then [add a Linux machine](linux-agent.md) or [a macOS machine](macos-agent.md).

## Native notifications

After pairing works, follow [APNs setup](notifications.md) to configure the
existing Hub with your Apple provider key. No second Hub or enrollment reset is
required.
