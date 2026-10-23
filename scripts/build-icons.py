#!/usr/bin/env python3
"""Render the original MIT-licensed SVG with the built-in sips tool; build web PNGs and an app-icon ICNS.
Run from any directory: python3 scripts/build-icons.py. No third-party packages required.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / 'artwork/hot-take-master.png'  # 1024 px: flame on the tile, with transparent margins

def run(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)

with tempfile.TemporaryDirectory(prefix='relaytake-icons-') as folder:
    temp = Path(folder)
    dock = temp / 'dock.png'
    browser = temp / 'web.png'
    run('sips', '-z', '1024', '1024', str(MASTER), '--out', str(dock))
    # The web variant is the tile alone: crop the 100 px margin on each side (824 of 1024).
    run('sips', '-c', '824', '824', str(dock), '--out', str(browser))
    run('sips', '-z', '256', '256', str(browser), '--out', str(browser))
    import base64
    favicon = base64.b64encode(browser.read_bytes()).decode()
    (ROOT / 'public/favicon.svg').write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        'width="256" height="256" viewBox="0 0 256 256">'
        f'<image width="256" height="256" href="data:image/png;base64,{favicon}" xlink:href="data:image/png;base64,{favicon}"/></svg>')
    iconset = temp / 'AppIcon.iconset'
    iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = size * scale
            suffix = '@2x' if scale == 2 else ''
            run('sips', '-z', str(pixels), str(pixels), str(dock), '--out', str(iconset / f'icon_{size}x{size}{suffix}.png'))
    resources = ROOT / 'mac/Resources'
    resources.mkdir(exist_ok=True)
    run('iconutil', '-c', 'icns', str(iconset), '-o', str(resources / 'AppIcon.icns'))
    run('sips', '-z', '1024', '1024', str(dock), '--out', str(resources / 'AppIcon.png'))
    for size in (16, 32, 48, 128):
        run('sips', '-z', str(size), str(size), str(browser), '--out', str(ROOT / f'public/icons/icon-{size}.png'))
print('Updated favicon, extension PNGs, and Mac AppIcon.icns / AppIcon.png.')
