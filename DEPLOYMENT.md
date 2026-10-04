# Deployment commands

These commands are instructions to run after reviewing the local validation. No Wi-Fi, routing, firewall, NetworkManager or VPN settings were changed during implementation. The configured SSH aliases `zima`/`spark`/`macbook` may need updating outside Relay if their addresses have changed. Current Zima connectivity could not be established, so no remote install is claimed.

## Zima: Linux amd64 hub

Run as the ordinary hub user on the Zima. Replace the example origin with an **existing HTTPS endpoint** that forwards to localhost:8787:

```sh
git clone https://github.com/mothx9/codex-relay.git
cd codex-relay
./scripts/install.sh hub --public-url https://relay.example.net
sudo loginctl enable-linger "$(id -un)"
systemctl --user status codex-relay-hub
```

The installer downloads and verifies the Linux amd64 prerelease. It requires curl, install, systemd and sha256sum, not Go/Node. Bootstrap token and DB are in `~/.local/share/codex-relay/hub`. Read the bootstrap token locally for login.

Create the three distinct agent tokens **on Zima**:

```sh
mkdir -p "$HOME/relay-enrollment"
chmod 700 "$HOME/relay-enrollment"
for machine in exon spark macbook; do
  "$HOME/.local/bin/codex-relay" token add \
    --data-dir "$HOME/.local/share/codex-relay/hub" \
    --machine "$machine" --out "$HOME/relay-enrollment/$machine.token"
done
```

## Transfer tokens

From Exon, using trusted, working SSH aliases:

```sh
mkdir -p "$HOME/.config/codex-relay"
chmod 700 "$HOME/.config/codex-relay"
scp zima:relay-enrollment/exon.token "$HOME/.config/codex-relay/exon.token"
chmod 600 "$HOME/.config/codex-relay/exon.token"

ssh spark 'mkdir -p "$HOME/.config/codex-relay"; chmod 700 "$HOME/.config/codex-relay"'
scp zima:relay-enrollment/spark.token /tmp/codex-relay-spark.token
chmod 600 /tmp/codex-relay-spark.token
scp /tmp/codex-relay-spark.token spark:.config/codex-relay/spark.token
ssh spark 'chmod 600 "$HOME/.config/codex-relay/spark.token"'
rm /tmp/codex-relay-spark.token

ssh macbook 'mkdir -p "$HOME/.config/codex-relay"; chmod 700 "$HOME/.config/codex-relay"'
scp zima:relay-enrollment/macbook.token /tmp/codex-relay-macbook.token
chmod 600 /tmp/codex-relay-macbook.token
scp /tmp/codex-relay-macbook.token macbook:.config/codex-relay/macbook.token
ssh macbook 'chmod 600 "$HOME/.config/codex-relay/macbook.token"'
rm /tmp/codex-relay-macbook.token
```

Then remove enrollment staging files on Zima after successful target enrollment. No token is passed as a command-line argument or printed to logs.

## Exon: Linux amd64 agent

On Exon, from the clone (or reuse the already-built independent checkout):

```sh
codex --version
codex app-server daemon version
# Start only if needed; do not restart active work:
codex app-server daemon start
./scripts/install.sh agent --hub-url https://relay.example.net \
  --machine exon --token-file "$HOME/.config/codex-relay/exon.token"
sudo loginctl enable-linger "$(id -un)"
systemctl --user status codex-relay-agent
```

## Spark: Linux arm64 agent

On Spark:

```sh
git clone https://github.com/mothx9/codex-relay.git
cd codex-relay
codex --version
codex app-server daemon start
./scripts/install.sh agent --hub-url https://relay.example.net \
  --machine spark --token-file "$HOME/.config/codex-relay/spark.token"
sudo loginctl enable-linger "$(id -un)"
systemctl --user status codex-relay-agent
```

The installer selects Linux arm64. A fixed node may use an HTTPS LAN origin if that certificate/origin is configured; no URL is hardcoded in the agent.

## MacBook: macOS arm64 agent

On MacBook, as the logged-in Codex user:

```sh
git clone https://github.com/mothx9/codex-relay.git
cd codex-relay
codex --version
codex app-server daemon start
./scripts/install.sh agent --hub-url https://relay.example.net \
  --machine macbook --token-file "$HOME/.config/codex-relay/macbook.token"
launchctl print "gui/$(id -u)/net.codex-relay.agent"
```

The installer selects macOS arm64, captures the current Codex executable/PATH, and writes a launchd user agent. It can reconnect through a roaming Tailscale route to the same HTTPS origin. It does not choose networks or change VPN settings.

## Recommended HTTPS with Tailscale Serve

Relay is independent of Tailscale. If choosing Tailscale Serve, first inspect existing Serve configuration to avoid replacing another site's mapping. These are **operator network-deployment commands**, not commands run by the Relay installer:

```sh
tailscale serve status
# Only after deciding this HTTPS mapping is available:
tailscale serve --bg --https=443 http://127.0.0.1:8787
```

Use the exact HTTPS URL that Serve reports as the hub's `--public-url` and every agent's `--hub-url`. If the root mapping is occupied, select another supported port/origin or use a dedicated reverse proxy; Relay does not support a subpath base URL. Connect the iPhone through the appropriate existing route, add the HTTPS app to Home Screen, enable push, close it, and check a real Needs You notification/deep link.

## Verify and revoke

```sh
"$HOME/.local/bin/codex-relay" doctor --hub-url https://relay.example.net \
  --machine exon --token-file "$HOME/.config/codex-relay/exon.token"
# On Zima:
"$HOME/.local/bin/codex-relay" token revoke \
  --data-dir "$HOME/.local/share/codex-relay/hub" --machine macbook
```

No account re-login is needed by Relay: local Codex must already be authenticated. Upgrade the binary by rerunning the installer with `RELAY_VERSION=<release tag>`; retain the state directory and VAPID keys. Linux agent failure/reconnect is automatic; on macOS launchd handles process restart while the user session is active.
