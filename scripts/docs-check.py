#!/usr/bin/env python3
"""Check repository-local Markdown and HTML links, including image assets."""
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
files = [root / p for p in subprocess.check_output(['git', 'ls-files', '*.md'], cwd=root, text=True).splitlines()]
# Include new guides before their first commit as well.
files = sorted(set(files) | set((root / 'docs').rglob('*.md')))
errors = []
checked = 0
for path in files:
    if not path.exists():
        continue
    content = re.sub(r'```.*?```', '', path.read_text(), flags=re.S)
    urls = re.findall(r'\]\(([^\s)]+)(?:\s+"[^"]*")?\)', content)
    urls += re.findall(r'(?:src|href)=["\']([^"\']+)["\']', content)
    for url in urls:
        parsed = urlsplit(url)
        if parsed.scheme or parsed.netloc or not parsed.path:
            continue
        target = (path.parent / unquote(parsed.path)).resolve()
        checked += 1
        if not target.exists():
            errors.append(f'{path.relative_to(root)}: missing {url}')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    raise SystemExit(1)
print(f'{checked} repository-local documentation links checked')
