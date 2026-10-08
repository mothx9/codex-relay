# Add a Linux machine

Install and sign in to Codex normally as the same OS user who will run Relay.
Use an existing shared Codex daemon. Relay will not start or restart it. The
machine needs outbound HTTPS access to your Hub; it needs no inbound Relay port.

1. On the paired iPhone, open **Relay menu → Machines → Add a machine**.
2. Choose a display name and a unique machine ID (letters, digits, `_` or `-`).
3. Create the one-time Agent code.
4. On that machine, download the installer and enroll with the guided option:

```sh
curl -fL https://github.com/mothx9/codex-relay/releases/download/v0.1.0/install.sh -o install.sh
sh install.sh agent \
  --hub-url "$RELAY_HUB_URL" --machine workstation --pair
```

Enter the code at the prompt. It is read from stdin, not a shell argument.
Enrollment creates a private credential file automatically; only after success
does the installer write/start the service. Existing credentials or an existing
Agent service cannot be overwritten by `--pair`.

Open Fleet. The machine progresses through **Syncing → Online** after a fresh
Codex snapshot. **Degraded** means the Agent is reachable but its Codex runtime
is unavailable. **Offline** means Relay cannot currently reach the Agent.

```sh
systemctl --user status codex-relay-agent
journalctl --user -u codex-relay-agent
```

The advanced/manual workflow remains available:

```sh
codex-relay pair --kind agent --hub-url "$RELAY_HUB_URL" \
  --machine workstation --code-stdin \
  --out "$HOME/.config/codex-relay/workstation.token"
sh install.sh agent \
  --hub-url "$RELAY_HUB_URL" --machine workstation \
  --token-file "$HOME/.config/codex-relay/workstation.token"
```

For upgrades, use the existing token file, not a new pairing code. See
[downloads](downloads.md) for package selection and [Hub setup](hub.md) for HTTPS prerequisites.
