#!/usr/bin/env python3
"""Render the shared vector mark. Requires librsvg's rsvg-convert (offline)."""
import json
import pathlib
import shutil
import subprocess
import copy
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/assets/app/mark.svg"
ICON = ROOT / "native/iOS/Assets.xcassets/AppIcon.appiconset"


def render(source, output, width, height):
    subprocess.run(["rsvg-convert", "-w", str(width), "-h", str(height), "-o", str(output), str(source)], check=True)


def readme_lockups():
    ns = "http://www.w3.org/2000/svg"
    ET.register_namespace("", ns)
    source = ET.parse(ROOT / "docs/assets/app/codex-app-icon.svg").getroot()
    for theme, color in (("light", "#17191c"), ("dark", "#f0f2f3")):
        root = ET.Element("{" + ns + "}svg", {"width": "460", "height": "96", "viewBox": "0 0 460 96", "role": "img", "aria-labelledby": "title"})
        ET.SubElement(root, "{" + ns + "}title", {"id": "title"}).text = "Codex Relay"
        mark = ET.SubElement(root, "{" + ns + "}g", {"transform": "translate(0 6) scale(3.5)"})
        for path in source.findall("{" + ns + "}path"):
            path = copy.deepcopy(path); path.set("fill", color); mark.append(path)
        ET.SubElement(root, "{" + ns + "}text", {"x": "104", "y": "65", "fill": color,
            "font-family": "Helvetica,Arial,sans-serif", "font-size": "51", "font-weight": "600", "letter-spacing": "-1.5"}).text = "Codex Relay"
        ET.ElementTree(root).write(ROOT / f"docs/assets/app/readme-{theme}.svg", encoding="unicode")


def main():
    readme_lockups()
    if not shutil.which("rsvg-convert"):
        raise SystemExit("Install librsvg (macOS: brew install librsvg), then rerun.")
    ICON.mkdir(parents=True, exist_ok=True)
    render(ROOT / "docs/assets/app/codex-app-icon.svg", ICON / "AppIcon.png", 1024, 1024)
    for size in (192, 512):
        render(SOURCE, ROOT / f"web/icon-{size}.png", size, size)
    shutil.copyfile(SOURCE, ROOT / "web/icon.svg")
    (ICON / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "Codex Relay", "version": 1}}, indent=2) + "\n")
    (ICON.parent / "Contents.json").write_text(json.dumps({"info": {"author": "Codex Relay", "version": 1}}, indent=2) + "\n")
    mark_set = ICON.parent / "RelayMark.imageset"
    mark_set.mkdir(exist_ok=True)
    shutil.copyfile(SOURCE, mark_set / "RelayMark.svg")
    (mark_set / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "RelayMark.svg", "idiom": "universal"}],
        "info": {"author": "Codex Relay", "version": 1},
        "properties": {"preserves-vector-representation": True}}, indent=2) + "\n")
    # Same source mark in the public social card; no real deployment data.
    mark = SOURCE.read_text().split('<rect width="1024"')[1].split('</svg>')[0]
    mark = '<rect width="1024"' + mark
    social = '''<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
<title>Codex Relay — your Codex fleet, on iPhone</title>
<rect width="1200" height="630" fill="#15181c"/>
<g transform="translate(60 140) scale(.32)">''' + mark + '''</g>
<g fill="#f0f2f3" font-family="-apple-system,BlinkMacSystemFont,Helvetica,Arial,sans-serif">
<text x="440" y="236" font-size="64" font-weight="700">Codex Relay</text>
<text x="444" y="313" font-size="32">Your Codex fleet. On iPhone.</text>
<text x="444" y="386" font-size="22" fill="#afb5bf">Live work · Decisions · Conversations</text>
<text x="444" y="470" font-size="19" fill="#afb5bf">Self-hosted · Open source</text>
</g></svg>'''
    social_source = ROOT / "docs/assets/app/social-preview.svg"
    social_source.write_text(social)
    render(social_source, ROOT / "docs/assets/app/social-preview.png", 1200, 630)


if __name__ == "__main__":
    main()
