# Upgrading an existing Relay

Keep the existing Hub identity, state directory, SQLite database, enrollment,
VAPID keys and optional APNs configuration. Upgrade the Hub in place; do not
create another installation to test a binary.

1. Review release compatibility and save the current binary/service configuration.
2. Back up SQLite consistently (SQLite backup API or a stopped service); copying
   only a live main DB file can omit WAL data. Keep backups private.
3. Install the verified binary for the Hub platform and restart only the Hub.
4. Check `/healthz`, authenticated Diagnostics and the expected version. Machines
   re-enter Syncing and become Online after fresh accepted snapshots.
5. Upgrade one Agent at a time with its existing token, state path and service
   configuration. Check version, Online state, sessions and live events before
   the next machine.
6. Build/install the native client through Xcode, preserving its Keychain. Verify
   existing pairing, foreground rehydration and representative control flows.

Do not restart shared Codex daemons as an upgrade shortcut. Pausing Relay or
restarting its Agent does not stop local Codex work. Do not rotate credentials,
change networking or re-enroll machines merely to update binaries.

The installer supports `--binary` for a reviewed local build and `--dry-run` to
inspect changes. Initial `agent --pair` deliberately refuses an already enrolled
installation; use the existing installation path for upgrades, not a new code.
Read `scripts/install.sh --help` and preserve all service options, including
APNs configuration, before regenerating units.

Rollback requires the prior binary and a compatible database. Never overwrite
current SQLite with an old backup while newer service writes are active. Stop
only the affected Relay service and follow the release's migration notes.
