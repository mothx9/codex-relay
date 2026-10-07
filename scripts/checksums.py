#!/usr/bin/env python3
"""Write checksums for the exact supported release binaries, never stale extras."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'dist'
names = [f'codex-relay-{target}' for target in ('darwin-arm64', 'linux-amd64', 'linux-arm64')]
lines = []
for name in names:
    path = root / name
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f'Missing release binary: {path}')
    lines.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {name}')
(root / 'SHA256SUMS').write_text('\n'.join(lines) + '\n')
print('Wrote SHA256SUMS for three target binaries')
