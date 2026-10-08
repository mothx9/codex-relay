#!/usr/bin/env python3
"""Verify release isolation, executable archives and unsigned device packaging."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import tarfile
import tempfile
import unittest
import zipfile
from release import package, TARGETS
from native_package import validate_app_archive


class ReleaseTests(unittest.TestCase):
    def test_archives_and_manifest_exclude_stale_files_and_are_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir(); (root / 'docs/setup').mkdir(parents=True)
            (root / 'scripts/install.sh').write_text('installer')
            (root / 'docs/setup/downloads.md').write_text('instructions')
            (root / 'LICENSE').write_text('license')
            output = root / 'dist'; output.mkdir()
            (output / 'old-secret.token').write_text('excluded')
            for target in TARGETS:
                (output / f'codex-relay-{target}').write_bytes(target.encode())
            names = package(root, output, '0.1.0', 'a' * 40)
            first = (output / 'SHA256SUMS').read_bytes()
            self.assertNotIn('old-secret.token', names)
            for line in first.decode().splitlines():
                digest, name = line.split('  ')
                self.assertEqual(digest, hashlib.sha256((output / name).read_bytes()).hexdigest())
            manifest = json.loads((output / 'release.json').read_text())
            self.assertEqual(manifest['tag'], 'v0.1.0')
            for target in TARGETS:
                with tarfile.open(output / f'codex-relay-0.1.0-{target}.tar.gz') as archive:
                    self.assertEqual(archive.getnames(), ['codex-relay', 'install.sh', 'LICENSE', 'INSTALL.md'])
                    self.assertEqual(archive.getmember('codex-relay').mode, 0o755)
                    self.assertEqual(archive.extractfile('codex-relay').read(), target.encode())
            package(root, output, '0.1.0', 'a' * 40)
            self.assertEqual(first, (output / 'SHA256SUMS').read_bytes())
            with self.assertRaises(ValueError): package(root, output, '../invalid', 'a' * 40)

    def test_ipa_rejects_simulator_wrong_version_and_signing_material(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.ipa'
            for platform, version, personal, valid in [('iPhoneOS', '0.1.0', False, True),
                    ('iPhoneSimulator', '0.1.0', False, False),
                    ('iPhoneOS', '9.0.0', False, False), ('iPhoneOS', '0.1.0', True, False)]:
                info = dict(CFBundleIdentifier='net.codex-relay.iphone', CFBundleExecutable='CodexRelay',
                            CFBundleShortVersionString=version, CFBundleSupportedPlatforms=[platform])
                with zipfile.ZipFile(path, 'w') as archive:
                    archive.writestr('Payload/CodexRelay.app/Info.plist', plistlib.dumps(info))
                    archive.writestr('Payload/CodexRelay.app/CodexRelay', struct.pack('<II', 0xFEEDFACF, 0x0100000C))
                    if personal: archive.writestr('Payload/CodexRelay.app/embedded.mobileprovision', 'private')
                if valid: validate_app_archive(path, '0.1.0')
                else:
                    with self.assertRaises(ValueError): validate_app_archive(path, '0.1.0')


if __name__ == '__main__': unittest.main()
