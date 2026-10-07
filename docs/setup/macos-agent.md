# Add a macOS machine

Use the same user account as local Codex. Start/sign in to Codex through its own
supported workflow and use its existing shared daemon. Relay never restarts that
daemon to install an Agent.

Create an Agent code in **Relay menu → Machines → Add a machine** on your paired
iPhone. With the matching macOS arm64 candidate binary available locally:

```sh
./scripts/install.sh agent --binary ./bin/codex-relay \
  --hub-url "$RELAY_HUB_URL" --machine laptop --pair
```

Enter the one-time code when prompted. The installer stores the credential with
mode `0600`, installs `~/.local/bin/codex-relay`, and creates the LaunchAgent
`~/Library/LaunchAgents/net.codex-relay.agent.plist`.

The Agent runs while that user is logged in. Sleep disconnects it; wake triggers
reconnect and a fresh snapshot before Online. Last-known Working does not imply
the sleeping machine is reachable.

```sh
launchctl print "gui/$(id -u)/net.codex-relay.agent"
```

Use `--dry-run` to inspect the service definition without enrollment or writes.
For updates, provide `--token-file` pointing to the existing private credential
instead of `--pair`. Do not erase the Hub database or enroll a second identity
merely to upgrade. See [Linux Agent setup](linux-agent.md) for the compatible
manual code-redemption workflow.
