#!/usr/bin/env python3
"""Record the isolated native product walkthrough and export reviewable public media."""
import argparse
import json
import os
from pathlib import Path
import signal
import select
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator', required=True)
parser.add_argument('--derived-data', default='/tmp/relay-public-screenshots-build')
parser.add_argument('--watcher-pid', type=int)
parser.add_argument('--skip-build', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
os.chdir(root)
base = ['xcodebuild', '-project', 'native/CodexRelay.xcodeproj', '-scheme', 'CodexRelay',
        '-destination', f'platform=iOS Simulator,id={args.simulator}', '-derivedDataPath', args.derived_data]
recording = None
paused = False
try:
    if args.watcher_pid:
        os.kill(args.watcher_pid, signal.SIGSTOP)
        paused = True
    if not args.skip_build:
        subprocess.run(base + ['CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'build-for-testing'], check=True)
    subprocess.run(['xcrun', 'simctl', 'status_bar', args.simulator, 'override', '--time', '9:41',
                    '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3',
                    '--batteryState', 'charged', '--batteryLevel', '100'], check=True)
    with tempfile.TemporaryDirectory(prefix='relay-walkthrough-') as temp:
        temp = Path(temp)
        raw, result, exported = temp / 'raw.mp4', temp / 'walkthrough.xcresult', temp / 'attachments'
        recording = subprocess.Popen(['xcrun', 'simctl', 'io', args.simulator, 'recordVideo',
                                      '--codec=h264', str(raw)], stderr=subprocess.PIPE, text=True)
        # simctl acknowledges the start before the test launch. Markers trim all launcher/private frames.
        deadline = time.monotonic() + 15
        while True:
            if not select.select([recording.stderr], [], [], max(0, deadline - time.monotonic()))[0]:
                raise RuntimeError('Simulator recording did not start')
            line = recording.stderr.readline()
            if 'Recording started' in line:
                started = time.time()
                break
            if recording.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('Simulator recording did not start')
        try:
            subprocess.run(base + ['-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
                                   '-resultBundlePath', str(result),
                                   '-only-testing:CodexRelayUITests/LiveAcceptanceTests/testPublicProductWalkthrough',
                                   'test-without-building'], check=True)
        finally:
            recording.send_signal(signal.SIGINT)
            recording.communicate(timeout=20)
            recording = None
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                        '--output-path', str(exported)], check=True)
        markers = {}
        for test in json.loads((exported / 'manifest.json').read_text()):
            for item in test['attachments']:
                for marker in ('start', 'end'):
                    if item['suggestedHumanReadableName'].startswith('Public walkthrough ' + marker + '_'):
                        markers[marker] = item['timestamp']
        if set(markers) != {'start', 'end'} or markers['end'] <= markers['start'] or markers['start'] <= started:
            raise RuntimeError('Missing safe recording boundaries')
        target = root / 'docs/assets/app/recordings'
        target.mkdir(parents=True, exist_ok=True)
        movie, preview = target / 'native-walkthrough.mp4', target / 'native-walkthrough.gif'
        # The recording acknowledgement is not an exact first-frame timestamp.
        # Leave a tail margin before XCTest tears down the app to exclude Home.
        duration = markers['end'] - markers['start'] - 2.25
        if duration <= 0:
            raise RuntimeError('Walkthrough is too short for safe recording boundaries')
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss',
                        str(max(0, markers['start'] - started + .25)), '-i', str(raw),
                        '-t', str(duration), '-an',
                        '-vf', 'scale=590:-2', '-r', '30', '-c:v', 'libx264', '-crf', '23',
                        '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(movie)], check=True)
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(movie),
                        '-filter_complex', 'fps=8,scale=280:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer',
                        '-loop', '0', str(preview)], check=True)
        subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration,size',
                        '-of', 'json', str(movie)], check=True)
        print('Review the full recording before publication:', movie)
finally:
    if recording is not None:
        recording.send_signal(signal.SIGINT)
        recording.communicate(timeout=20)
    subprocess.run(['xcrun', 'simctl', 'status_bar', args.simulator, 'clear'], check=False)
    if paused:
        os.kill(args.watcher_pid, signal.SIGCONT)
    subprocess.run(['xcrun', 'simctl', 'launch', args.simulator, 'net.codex-relay.iphone'], check=False)
