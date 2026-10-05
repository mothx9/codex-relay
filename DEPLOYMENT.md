# Deployment commands

The installer does not change Wi-Fi, routing, firewall, NetworkManager or VPN settings. SSH aliases below must already point to reachable, trusted hosts. A hub can technically run on any supported host. The reference installation uses **Zima as the sole canonical always-on hub** and Exon/Spark/MacBook only as agents. The existing Exon loopback hub is a validation rollback, not a second production fleet. Do not activate agents against an assumed URL or transfer old validation tokens as Zima credentials.

## Zima recovery and cutover boundary

The 2026-10-05 recovery restored trusted SSH and normal Debian boot. Alfa USB ID `0bda:0811` identifies AWUS036ACS / RTL8811AU; the host uses the DKMS `rtl8821au/5.12.5.2` driver with a persistent NetworkManager profile, power saving disabled and a 20 MHz channel limit. Wi-Fi SSH, DNS/HTTPS and bounded packet-loss checks passed while temporary Ethernet remained connected. The user hub unit is prepared but inactive/disabled, linger is enabled, and an unused Tailscale Serve origin has been configured for its loopback listener. Ethernet-removal acceptance is required before activation. No Wi-Fi credentials, private keys or runtime state are stored in this repository.

Before installation, obtain trusted SSH to Zima. If the headless host has no working route, temporary Ethernet is the only initial recovery path available remotely. A USB Wi-Fi adapter alone cannot be configured through a disconnected host.

Collect `uname -a`, `/etc/os-release`, `lsusb`, `ip -br link`, `ip -br addr`, `ip route`, `iw dev`, `rfkill list`, `nmcli general status`, `nmcli device` and NetworkManager service status. Identify the actual Alfa USB ID, driver and interface before choosing a driver. Configure Wi-Fi persistently with the host's existing network manager, keeping credentials out of command arguments/logs and preserving Ethernet. Prove a **new SSH connection via the Wi-Fi IP**, DNS and Internet access before disconnecting Ethernet; repeat those checks afterwards.

Inspect `tailscale status`, `tailscale ping` and `tailscale serve status` on the recovered Zima. Use its existing routing and an available HTTPS Serve mapping; do not overwrite another service. The hub remains loopback-only. The one stable HTTPS origin belongs to Zima and is shared by operator PWA and all three outbound agents.

Install Zima's persistent hub first; verify service restart, linger, DB recovery and stable bootstrap/VAPID files. Enroll Exon on this hub, then prove real snapshot/chat/follow-up/answer/reconnect before stopping the old Exon hub. Retain its private state directory temporarily for rollback. Enroll Spark next, then MacBook. An unreachable Zima blocks this cutover; a staged binary or unit is not an online fleet.

## Prerequisites and setup order

1. Start one hub and provide a working HTTPS endpoint forwarding to its loopback listener.
2. Create distinct agent tokens **on that active hub**, using its actual data directory.
3. Securely copy each token to the corresponding machine.
4. Install/start agents with that same hub's HTTPS URL.

Cloning this repository does not create an agent token or a service. A token from a different hub/data directory will be rejected. Do not rerun `token add` for an already-enrolled machine merely to copy its existing token: that rotates the credential.

In each target shell, set the actual URL reported by your existing reverse proxy or Tailscale Serve:

```sh
printf 'Existing HTTPS hub URL: '
IFS= read -r RELAY_HUB_URL
export RELAY_HUB_URL
```

The commands below require this variable; there is no copy-paste example domain to accidentally use. The installer rejects reserved documentation domains before creating files.

## Zima: Linux amd64 hub

Run as the ordinary hub user on the reachable Zima, with an **existing HTTPS endpoint** that forwards to localhost:8787:

```sh
git clone https://github.com/mothx9/codex-relay.git
cd codex-relay
./scripts/install.sh hub --public-url "${RELAY_HUB_URL:?Set the actual HTTPS hub URL first}"
sudo loginctl enable-linger "$(id -un)"
systemctl --user status codex-relay-hub
```

The installer downloads and verifies the Linux amd64 prerelease. It requires curl, install, systemd and sha256sum, not Go/Node. Bootstrap token and DB are in `~/.local/share/codex-relay/hub`. Read the bootstrap token locally for login.

Create the three distinct agent tokens **on the active hub** (Zima in this deployment). Use its actual data directory if it differs from this installed-service default:

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

From Exon, using trusted, working SSH aliases. Here `zima` is the active hub; substitute the actual hub's alias and enrollment paths if you started elsewhere. Do not provision a second hub simply to obtain tokens:

```sh
mkdir -p "$HOME/.config/codex-relay"
chmod 700 "$HOME/.config/codex-relay"
umask 077
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
./scripts/install.sh agent --hub-url "${RELAY_HUB_URL:?Set the actual HTTPS hub URL first}" \
  --machine exon --token-file "$HOME/.config/codex-relay/exon.token"
sudo loginctl enable-linger "$(id -un)"
systemctl --user status codex-relay-agent
```

## Spark: Linux arm64 agent

On Spark, **after transferring its hub-issued token** to `~/.config/codex-relay/spark.token`:

```sh
git clone https://github.com/mothx9/codex-relay.git
cd codex-relay
codex --version
codex app-server daemon start
./scripts/install.sh agent --hub-url "${RELAY_HUB_URL:?Set the actual HTTPS hub URL first}" \
  --machine spark --token-file "$HOME/.config/codex-relay/spark.token"
sudo loginctl enable-linger "$(id -un)"
systemctl --user status codex-relay-agent
```

The installer selects Linux arm64. If the repository already exists, enter it and run `git pull --ff-only` instead of cloning again. A fixed node may use an HTTPS LAN origin if that certificate/origin is configured; no URL is hardcoded in the agent.

If HTTPS is still being prepared, Linux can install the binary, token and unit without starting it: add `--no-start` to the agent installation command. This does not enable the unit or stop an existing service. Once the configured endpoint is ready, run:

```sh
systemctl --user enable --now codex-relay-agent.service
systemctl --user status codex-relay-agent.service
```

`Token file does not exist` from older installers means enrollment has not reached this machine: no unit was installed, so `Unit ... could not be found` is expected. Transfer the existing token from the correct hub before retrying. The current installer reports the missing path and this prerequisite explicitly. `linger` only keeps the user service manager running after logout; it does not enroll an agent or create a unit.

## MacBook: macOS arm64 agent

On MacBook, as the logged-in Codex user, after transferring its hub-issued token:

```sh
git clone https://github.com/mothx9/codex-relay.git
cd codex-relay
codex --version
codex app-server daemon start
./scripts/install.sh agent --hub-url "${RELAY_HUB_URL:?Set the actual HTTPS hub URL first}" \
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
"$HOME/.local/bin/codex-relay" doctor --hub-url "${RELAY_HUB_URL:?Set the actual HTTPS hub URL first}" \
  --machine exon --token-file "$HOME/.config/codex-relay/exon.token"
# On Zima:
"$HOME/.local/bin/codex-relay" token revoke \
  --data-dir "$HOME/.local/share/codex-relay/hub" --machine macbook
```

No account re-login is needed by Relay: local Codex must already be authenticated. Upgrade the binary by rerunning the installer with `RELAY_VERSION=<release tag>`; retain the state directory and VAPID keys. Linux agent failure/reconnect is automatic; on macOS launchd handles process restart while the user session is active.
