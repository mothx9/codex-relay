#!/usr/bin/env python3
"""Capture sanitized product views on an iPhone 16 simulator; never pair a Hub."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator', required=True, help='Booted iPhone 16 simulator UDID')
parser.add_argument('--derived-data', default='/tmp/relay-public-screenshots-build')
parser.add_argument('--watcher-pid', type=int, help='Pause an existing development watcher during capture')
parser.add_argument('--skip-build', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
os.chdir(root)
base = ['xcodebuild', '-project', 'native/CodexRelay.xcodeproj', '-scheme', 'CodexRelay', '-destination', f'platform=iOS Simulator,id={args.simulator}', '-derivedDataPath', args.derived_data]

def run(command):
    subprocess.run(command, check=True)

paused = False
try:
    if args.watcher_pid:
        os.kill(args.watcher_pid, signal.SIGSTOP)
        paused = True
    if not args.skip_build:
        run(base + ['CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'build-for-testing'])
    run(['xcrun', 'simctl', 'status_bar', args.simulator, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'charged', '--batteryLevel', '100'])
    with tempfile.TemporaryDirectory(prefix='relay-public-screenshots-') as temp:
        result = Path(temp) / 'capture.xcresult'
        run(base + ['-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never', '-resultBundlePath', str(result), '-only-testing:CodexRelayUITests/LiveAcceptanceTests/testPublicProductScreenshots', 'test-without-building'])
        exported = Path(temp) / 'attachments'
        run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(exported)])
        target = root / 'docs/assets/app/screenshots'
        target.mkdir(parents=True, exist_ok=True)
        names = {'fleet', 'conversation', 'needs-you', 'question', 'terminal', 'tools', 'diff', 'machines', 'account', 'settings', 'diagnostics', 'pairing', 'navigation', 'machine-diagnostics'}
        captured = set()
        for test in json.loads((exported / 'manifest.json').read_text()):
            if test['testIdentifier'] != 'LiveAcceptanceTests/testPublicProductScreenshots()':
                continue
            for attachment in test['attachments']:
                name = attachment['suggestedHumanReadableName'].split('_')[0].removeprefix('public-')
                if name in names and not attachment.get('isAssociatedWithFailure', False):
                    shutil.copyfile(exported / attachment['exportedFileName'], target / f'{name}.png')
                    captured.add(name)
        if captured != names:
            raise SystemExit(f'Missing screenshots: {sorted(names - captured)}')
        print(f'Exported {len(captured)} sanitized screenshots to {target}')
finally:
    subprocess.run(['xcrun', 'simctl', 'status_bar', args.simulator, 'clear'], check=False)
    if paused:
        os.kill(args.watcher_pid, signal.SIGCONT)
    subprocess.run(['xcrun', 'simctl', 'launch', args.simulator, 'net.codex-relay.iphone'], check=False)
