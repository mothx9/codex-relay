#!/usr/bin/env python3
"""Package an exact, versioned release set; never publish stale dist files."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

TARGETS = ('darwin-arm64', 'linux-amd64', 'linux-arm64')
ROOT = Path(__file__).resolve().parents[1]


def package(root, output, version, commit, ipa=None):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', version):
        raise ValueError('Expected a semantic release version without the v prefix')
    output.mkdir(parents=True, exist_ok=True)
    names = []
    for target in TARGETS:
        binary = output / f'codex-relay-{target}'
        if not binary.is_file() or not binary.stat().st_size:
            raise ValueError(f'Missing binary: {binary}')
        name = f'codex-relay-{version}-{target}.tar.gz'
        # Neutral ownership, timestamps and flat layout make archives repeatable.
        with (output / name).open('wb') as destination:
            with gzip.GzipFile(filename='', mode='wb', fileobj=destination, mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode='w') as archive:
                    for filename, data, mode in (
                        ('codex-relay', binary.read_bytes(), 0o755),
                        ('install.sh', (root / 'scripts/install.sh').read_bytes(), 0o755),
                        ('LICENSE', (root / 'LICENSE').read_bytes(), 0o644),
                        ('INSTALL.md', (root / 'docs/setup/downloads.md').read_bytes(), 0o644),
                    ):
                        entry = tarfile.TarInfo(filename)
                        entry.size, entry.mode = len(data), mode
                        archive.addfile(entry, io.BytesIO(data))
        names.append(name)
    shutil.copyfile(root / 'scripts/install.sh', output / 'install.sh')
    names.append('install.sh')
    if ipa:
        from native_package import validate_app_archive
        validate_app_archive(ipa, version)
        name = f'CodexRelay-{version}-ios-unsigned.ipa'
        if ipa.resolve() != (output / name).resolve():
            shutil.copyfile(ipa, output / name)
        names.append(name)
    artifacts = [dict(name=name, size=(output / name).stat().st_size,
                      sha256=hashlib.sha256((output / name).read_bytes()).hexdigest())
                 for name in sorted(names)]
    manifest = dict(version=version, tag='v' + version, commit=commit,
                    artifacts=artifacts, ios_distribution='unsigned-sideload' if ipa else None)
    (output / 'release.json').write_text(json.dumps(manifest, indent=2) + '\n')
    names.append('release.json')
    (output / 'SHA256SUMS').write_text(''.join(
        f'{hashlib.sha256((output / name).read_bytes()).hexdigest()}  {name}\n'
        for name in sorted(names)))
    return names + ['SHA256SUMS']


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', default=(ROOT / 'VERSION').read_text().strip())
    parser.add_argument('--ipa', type=Path)
    args = parser.parse_args()
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    print('\n'.join(package(ROOT, ROOT / 'dist', args.version, commit, args.ipa)))
