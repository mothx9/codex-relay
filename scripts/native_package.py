#!/usr/bin/env python3
"""Create an unsigned device IPA without publishing personal signing material."""
import argparse
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def validate_app_archive(path, version):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip():
            raise ValueError('Corrupt IPA')
        names = archive.namelist()
        if any(not n.startswith('Payload/CodexRelay.app/') or '..' in Path(n).parts
               or n.endswith(('.mobileprovision', '.p8', '.p12', '.xcconfig'))
               or '_CodeSignature' in Path(n).parts for n in names):
            raise ValueError('IPA contains unexpected or personal signing files')
        info = plistlib.loads(archive.read('Payload/CodexRelay.app/Info.plist'))
        if (info.get('CFBundleIdentifier') != 'net.codex-relay.iphone'
                or info.get('CFBundleShortVersionString') != version
                or info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']):
            raise ValueError('IPA must contain the matching iPhone device build')
        executable = archive.read('Payload/CodexRelay.app/' + info['CFBundleExecutable'])
        if struct.unpack('<II', executable[:8]) != (0xFEEDFACF, 0x0100000C):
            raise ValueError('Expected an arm64 device Mach-O executable')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', default=(ROOT / 'VERSION').read_text().strip())
    parser.add_argument('--build-number', default='1')
    args = parser.parse_args()
    output = ROOT / 'dist' / f'CodexRelay-{args.version}-ios-unsigned.ipa'
    output.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='relay-unsigned-ios-') as temp:
        subprocess.run(['xcodebuild', '-project', str(ROOT / 'native/CodexRelay.xcodeproj'),
                        '-scheme', 'CodexRelay', '-configuration', 'Release',
                        '-sdk', 'iphoneos', '-destination', 'generic/platform=iOS',
                        '-derivedDataPath', temp, 'CODE_SIGNING_ALLOWED=NO',
                        'CODE_SIGN_ENTITLEMENTS=', 'DEVELOPMENT_TEAM=',
                        'MARKETING_VERSION=' + args.version,
                        'CURRENT_PROJECT_VERSION=' + args.build_number, 'build'], check=True)
        app = Path(temp) / 'Build/Products/Release-iphoneos/CodexRelay.app'
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(app.rglob('*')):
                if path.is_file():
                    if path.is_symlink():
                        raise ValueError('Unexpected symlink in device bundle')
                    archive.write(path, 'Payload/CodexRelay.app/' + str(path.relative_to(app)))
    validate_app_archive(output, args.version)
    print('Validated unsigned iPhone IPA:', output)
