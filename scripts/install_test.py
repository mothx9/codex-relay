#!/usr/bin/env python3
"""Exercise installation in a disposable root without touching the user's home."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="relay-installer-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.install_root = self.root / "installation"
        self.install_root.mkdir()
        self.mock = self.root / "mock"
        self.mock.mkdir()
        # Only substitute the filesystem root variable in this test copy. Keep
        # HOME unchanged; all validation/rendering/install logic is the source.
        self.installer = self.root / "install.sh"
        source = Path(__file__).with_name("install.sh").read_text()
        self.installer.write_text(source.replace("$HOME", "$RELAY_TEST_INSTALL_ROOT"))
        self.script("uname", 'case "$1" in -s) echo Linux;; -m) echo x86_64;; esac')
        self.script("systemctl", 'printf "%s\\n" "$*" >> "$RELAY_TEST_INSTALL_ROOT/systemctl.calls"')
        self.binary = self.root / "candidate"
        self.binary.write_text("#!/bin/sh\nexit 0\n")
        self.binary.chmod(0o755)
        self.config = self.root / "APNs secrets %literal $TOKEN" / "config.json"
        self.config.parent.mkdir()
        self.config.write_text('{"key_file":"owner-key.p8"}\n')
        self.config.chmod(0o600)
        self.env = dict(os.environ, RELAY_TEST_INSTALL_ROOT=str(self.install_root),
                        PATH=str(self.mock) + os.pathsep + os.environ["PATH"])

    def script(self, name, body):
        p = self.mock / name
        p.write_text("#!/bin/sh\n" + body + "\n")
        p.chmod(0o755)

    def run_install(self, *args, success=True, role="hub"):
        command = ["sh", str(self.installer), role, "--binary", str(self.binary)]
        if role == "hub":
            command += ["--public-url", "https://relay.test", "--no-start"]
        else:
            token = self.root / "agent.token"
            token.write_text("fictional-test-credential")
            token.chmod(0o600)
            command += ["--hub-url", "https://relay.test", "--machine", "test",
                        "--token-file", str(token), "--codex", "/bin/true", "--no-start"]
        result = subprocess.run(command + list(args), env=self.env, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    @property
    def unit(self):
        return self.install_root / ".config/systemd/user/codex-relay-hub.service"

    def test_persistent_apns_upgrade_and_explicit_disable_preserve_key(self):
        original = self.config.read_bytes()
        self.run_install("--apns-config", str(self.config))
        first = self.unit.read_text()
        self.assertIn("--apns-config", first)
        self.assertIn("%%literal $$TOKEN", first)
        record = self.install_root / ".config/codex-relay/apns-config.path"
        self.assertEqual(record.read_text().strip(), str(self.config))
        self.assertEqual(record.stat().st_mode & 0o777, 0o600)
        self.run_install()
        self.assertEqual(self.unit.read_text(), first)
        self.run_install("--apns-config", "none")
        self.assertNotIn("--apns-config", self.unit.read_text())
        self.assertEqual(record.read_text(), "\n")
        self.assertEqual(self.config.read_bytes(), original)
        self.assertEqual((self.install_root / "systemctl.calls").read_text().splitlines(),
                         ["--user daemon-reload"] * 3)

    def test_dry_run_writes_no_installation_files(self):
        result = self.run_install("--apns-config", str(self.config), "--dry-run")
        self.assertIn("--apns-config", result.stdout)
        self.assertEqual(list(self.install_root.iterdir()), [])

    def test_invalid_files_and_agent_flag_fail_before_installation(self):
        self.config.chmod(0o644)
        self.run_install("--apns-config", str(self.config), success=False)
        self.config.chmod(0o600)
        link = self.root / "symlink.json"
        link.symlink_to(self.config)
        self.run_install("--apns-config", str(link), success=False)
        self.run_install("--apns-config", str(self.config) + "\n", success=False)
        result = self.run_install("--apns-config", str(self.config), role="agent", success=False)
        self.assertIn("only valid for the Hub", result.stderr)
        self.assertEqual(list(self.install_root.iterdir()), [])

    def test_manual_service_setting_cannot_be_silently_dropped(self):
        self.unit.parent.mkdir(parents=True)
        original = 'ExecStart="/bin/relay" hub --apns-config "/private/config.json"\n'
        self.unit.write_text(original)
        self.run_install(success=False)
        self.assertEqual(self.unit.read_text(), original)
        self.assertFalse((self.install_root / ".local").exists())
        self.run_install("--apns-config", str(self.config))
        self.assertIn("--apns-config", self.unit.read_text())


if __name__ == "__main__":
    unittest.main()
