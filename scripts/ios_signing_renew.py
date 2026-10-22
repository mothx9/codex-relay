#!/usr/bin/env python3
"""Renew a Personal Team iPhone install before its seven-day profile expires.

The local LaunchAgent runs a pinned source snapshot. It never installs whatever
uncommitted work happens to be in the developer's checkout on renewal day.
"""

import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile


BUNDLE_ID = "net.codex-relay.iphone"
REPO = Path(__file__).resolve().parent.parent
STATE_DIR = Path.home() / "Library/Application Support/CodexRelay/iPhoneSigningGuard"
PROFILE_DIRS = (
    Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    Path.home() / "Library/MobileDevice/Provisioning Profiles",
)
RENEW_BEFORE = dt.timedelta(days=3)
CHECK_INTERVAL_SECONDS = 15 * 60
ALERT_INTERVAL = dt.timedelta(days=1)


def run(args, *, timeout=60, output=None):
    if output is None:
        return subprocess.run(args, check=True, capture_output=True, text=True, timeout=timeout).stdout
    with open(output, "w") as log:
        subprocess.run(args, check=True, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)


def profile(path):
    data = subprocess.run(
        ["/usr/bin/security", "cms", "-D", "-i", str(path)],
        check=True, capture_output=True, timeout=15,
    ).stdout
    return plistlib.loads(data)


def expires_at(value):
    if isinstance(value, dt.datetime):
        return value.replace(tzinfo=dt.timezone.utc) if value.tzinfo is None else value
    return dt.datetime.fromisoformat(value).astimezone(dt.timezone.utc)


def renewal_due(now, installed_expiry, force=False):
    return force or now + RENEW_BEFORE >= installed_expiry


def matching_profile(value):
    identifier = value.get("Entitlements", {}).get("application-identifier", "")
    return identifier.endswith("." + BUNDLE_ID)


def cached_profiles():
    found = []
    for root in PROFILE_DIRS:
        for path in root.glob("*.mobileprovision"):
            try:
                value = profile(path)
            except (OSError, subprocess.SubprocessError, ValueError, plistlib.InvalidFileException):
                continue
            if matching_profile(value):
                found.append(path)
    return found


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    os.chmod(temporary, 0o600)
    temporary.replace(path)


def get_config():
    return json.loads((STATE_DIR / "config.json").read_text())


def record(config, status, detail=""):
    write_json(STATE_DIR / "status.json", {
        "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "installed_profile_expires_at": config["installed_profile_expires_at"],
        "status": status,
        "detail": detail,
    })
    print(status + (": " + detail if detail else ""), flush=True)


def alert_stage(now, expiry):
    if now >= expiry:
        return "expired"
    if renewal_due(now, expiry):
        return "due"
    return None


def should_alert(now, stage, previous):
    if not stage:
        return False
    if previous.get("stage") != stage:
        return True
    try:
        return now - expires_at(previous["alerted_at"]) >= ALERT_INTERVAL
    except (KeyError, TypeError, ValueError):
        return True


def post_alert(stage, message):
    now = dt.datetime.now(dt.timezone.utc)
    alert_file = STATE_DIR / "alert.json"
    try:
        previous = json.loads(alert_file.read_text())
    except (OSError, ValueError):
        previous = {}
    if not isinstance(previous, dict):
        previous = {}
    if not should_alert(now, stage, previous):
        return
    script = f'display notification "{message}" with title "Codex Relay"'
    try:
        run(["/usr/bin/osascript", "-e", script], timeout=15)
    except (OSError, subprocess.SubprocessError):
        return
    write_json(alert_file, {"stage": stage, "alerted_at": now.isoformat()})


def alert_unavailable(expiry):
    stage = alert_stage(dt.datetime.now(dt.timezone.utc), expiry)
    if stage == "expired":
        post_alert(stage, "Codex Relay has expired on iPhone. Connect and unlock it to reinstall.")
    elif stage == "due":
        post_alert(stage, "Connect and unlock your iPhone so Codex Relay can renew before expiry.")


def alert_failure():
    post_alert("renewal_failed", "Codex Relay could not renew. Check Xcode Accounts and the local build log.")


def alert_unverified():
    post_alert("launch_unverified", "Codex Relay was installed but launch is unverified. Open it on iPhone and check any trust prompt.")


def device_available(udid):
    with tempfile.TemporaryDirectory(prefix="relay-device-") as name:
        result = Path(name) / "devices.json"
        run(["/usr/bin/xcrun", "devicectl", "list", "devices", "--json-output", str(result)], timeout=30)
        devices = json.loads(result.read_text()).get("result", {}).get("devices", [])
        matches = [item for item in devices if item.get("hardwareProperties", {}).get("udid") == udid
                   and item.get("hardwareProperties", {}).get("reality") == "physical"]
        if len(matches) != 1 or matches[0].get("connectionProperties", {}).get("pairingState") != "paired":
            return False
        if matches[0].get("deviceProperties", {}).get("bootState") != "booted":
            return False
        try:
            run(["/usr/bin/xcrun", "devicectl", "device", "info", "apps", "--device", udid,
                 "--json-output", str(Path(name) / "apps.json")], timeout=45)
        except (subprocess.SubprocessError, OSError):
            return False
        return True


def snapshot_source(destination):
    if run(["/usr/bin/git", "-C", str(REPO), "status", "--porcelain"]).strip():
        raise RuntimeError("checkout has uncommitted changes; finish or stash them before setup")
    signing = REPO / "native/LocalSigning.xcconfig"
    if not signing.is_file():
        raise RuntimeError("native/LocalSigning.xcconfig is missing")
    head = run(["/usr/bin/git", "-C", str(REPO), "rev-parse", "HEAD"]).strip()
    with tempfile.TemporaryDirectory(prefix="relay-source-", dir=str(STATE_DIR)) as name:
        staged = Path(name) / "source"
        staged.mkdir()
        archive = subprocess.Popen(["/usr/bin/git", "-C", str(REPO), "archive", "--format=tar", head],
                                   stdout=subprocess.PIPE)
        with tarfile.open(fileobj=archive.stdout, mode="r|") as tar:
            for member in tar:
                parts = Path(member.name).parts
                if member.name.startswith("/") or ".." in parts or member.issym() or member.islnk():
                    raise RuntimeError("unsafe path in source archive")
                tar.extract(member, staged)
        if archive.wait() != 0:
            raise RuntimeError("git archive failed")
        shutil.copy2(signing, staged / "native/LocalSigning.xcconfig")
        os.chmod(staged / "native/LocalSigning.xcconfig", 0o600)
        if destination.exists():
            shutil.rmtree(destination)
        shutil.move(staged, destination)
    return head


def setup(udid, app):
    STATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(STATE_DIR, 0o700)
    if not device_available(udid):
        raise RuntimeError("the paired physical iPhone is not reachable")
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], timeout=30)
    embedded = profile(app / "embedded.mobileprovision")
    if not matching_profile(embedded) or udid not in embedded.get("ProvisionedDevices", []):
        raise RuntimeError("signed app does not match this bundle and device")
    commit = snapshot_source(STATE_DIR / "source")
    config = {
        "device_udid": udid,
        "source_commit": commit,
        "installed_profile_expires_at": expires_at(embedded["ExpirationDate"]).isoformat(),
        "last_installed_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    write_json(STATE_DIR / "config.json", config)
    record(config, "ready", "pinned source and installed signing profile recorded")
    install_launch_agent()


def launch_agent_value(interval=CHECK_INTERVAL_SECONDS):
    label = "net.codex-relay.ios-signing-renew"
    return {
        "Label": label,
        "ProgramArguments": ["/usr/bin/python3", str(Path(__file__).resolve()), "check"],
        "RunAtLoad": True,
        "StartInterval": interval,
        "StandardOutPath": str(STATE_DIR / "refresh.stdout.log"),
        "StandardErrorPath": str(STATE_DIR / "refresh.stderr.log"),
    }


def install_launch_agent():
    label = "net.codex-relay.ios-signing-renew"
    destination = Path.home() / "Library/LaunchAgents" / (label + ".plist")
    value = launch_agent_value()
    if destination.exists():
        with open(destination, "rb") as existing:
            old_value = plistlib.load(existing)
        if old_value == value:
            print("existing 15-minute LaunchAgent kept", flush=True)
            return
        if old_value != launch_agent_value(21600):
            raise RuntimeError("LaunchAgent differs from the known schedule; inspect it before replacing")
        run(["/bin/launchctl", "bootout", "gui/" + str(os.getuid()) + "/" + label])
        try:
            with open(destination, "wb") as output:
                plistlib.dump(value, output)
            os.chmod(destination, 0o600)
            run(["/bin/launchctl", "bootstrap", "gui/" + str(os.getuid()), str(destination)])
        except Exception:
            with open(destination, "wb") as output:
                plistlib.dump(old_value, output)
            os.chmod(destination, 0o600)
            run(["/bin/launchctl", "bootstrap", "gui/" + str(os.getuid()), str(destination)])
            raise
        print("updated LaunchAgent to check every 15 minutes", flush=True)
        return
    with open(destination, "wb") as output:
        plistlib.dump(value, output)
    os.chmod(destination, 0o600)
    try:
        run(["/bin/launchctl", "bootstrap", "gui/" + str(os.getuid()), str(destination)])
    except Exception:
        destination.unlink()
        raise
    print("scheduled every 15 minutes using " + str(destination), flush=True)


def verify_launch(config):
    """Only report a renewed install after iOS accepts a launch request."""
    try:
        run(["/usr/bin/xcrun", "devicectl", "device", "process", "launch",
             "--device", config["device_udid"], "--no-activate", BUNDLE_ID],
            timeout=60, output=STATE_DIR / "launch.log")
    except (OSError, subprocess.SubprocessError):
        record(config, "installed_unverified", "iOS did not accept launch; inspect launch.log and check any trust prompt on iPhone")
        alert_unverified()
        return False
    config.pop("pending_launch_validation", None)
    write_json(STATE_DIR / "config.json", config)
    (STATE_DIR / "alert.json").unlink(missing_ok=True)
    record(config, "renewed", "signed app installed and iOS accepted launch")
    return True


def refresh(config, force=False):
    udid = config["device_udid"]
    previous = expires_at(config["installed_profile_expires_at"])
    now = dt.datetime.now(dt.timezone.utc)
    pending = bool(config.get("pending_launch_validation")) and now < previous
    if not pending and not renewal_due(now, previous, force):
        record(config, "current", "next renewal when fewer than three days remain")
        return
    try:
        available = device_available(udid)
    except (OSError, subprocess.SubprocessError, ValueError):
        available = False
    if not available:
        detail = "connect and unlock the paired iPhone; will retry launch validation in 15 minutes" if pending else \
            "connect and unlock the paired iPhone; will retry in 15 minutes"
        record(config, "waiting_for_iphone", detail)
        if pending:
            alert_unverified()
        else:
            alert_unavailable(previous)
        return
    if pending:
        verify_launch(config)
        return

    backup = Path(tempfile.mkdtemp(prefix="profile-backup-", dir=str(STATE_DIR)))
    os.chmod(backup, 0o700)
    moved = []
    try:
        for item in cached_profiles():
            target = backup / (str(len(moved)) + "-" + item.name)
            shutil.move(item, target)
            moved.append((target, item))
        project = STATE_DIR / "source/native/CodexRelay.xcodeproj"
        app = STATE_DIR / "DerivedData/Build/Products/Debug-iphoneos/CodexRelay.app"
        run(["/usr/bin/xcodebuild", "-project", str(project), "-scheme", "CodexRelay",
             "-configuration", "Debug", "-destination", "platform=iOS,id=" + udid,
             "-derivedDataPath", str(STATE_DIR / "DerivedData"),
             "-allowProvisioningUpdates", "clean", "build"],
            timeout=1200, output=STATE_DIR / "build.log")
        embedded = profile(app / "embedded.mobileprovision")
        new_expiry = expires_at(embedded["ExpirationDate"])
        if not matching_profile(embedded) or udid not in embedded.get("ProvisionedDevices", []):
            raise RuntimeError("renewed app has the wrong bundle or device")
        if new_expiry <= previous or new_expiry <= dt.datetime.now(dt.timezone.utc) + RENEW_BEFORE:
            raise RuntimeError("Xcode did not extend the app profile expiry")
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], timeout=30)
        run(["/usr/bin/xcrun", "devicectl", "device", "install", "app", "--device", udid, str(app)],
            timeout=180, output=STATE_DIR / "install.log")
        config["installed_profile_expires_at"] = new_expiry.isoformat()
        config["last_installed_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
        config["pending_launch_validation"] = True
        write_json(STATE_DIR / "config.json", config)
        verify_launch(config)
    finally:
        for saved, original in moved:
            if not original.exists():
                shutil.move(saved, original)
            else:
                saved.unlink()
        shutil.rmtree(backup)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    setup_parser = sub.add_parser("setup", help="pin the currently installed app version")
    setup_parser.add_argument("--device", required=True)
    setup_parser.add_argument("--app", type=Path, required=True)
    check_parser = sub.add_parser("check", help="refresh when the installed profile is near expiry")
    check_parser.add_argument("--force", action="store_true", help="renew now for an end-to-end check")
    sub.add_parser("schedule", help="install or update the periodic LaunchAgent")
    args = parser.parse_args()
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(STATE_DIR, 0o700)
        with open(STATE_DIR / "lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if args.command == "setup":
                setup(args.device, args.app)
            elif args.command == "schedule":
                install_launch_agent()
            else:
                config = get_config()
                try:
                    refresh(config, force=args.force)
                except Exception as exc:
                    record(config, "failed", str(exc))
                    alert_failure()
                    raise
    except Exception as exc:
        print("iPhone signing renewal: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
