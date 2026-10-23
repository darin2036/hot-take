#!/usr/bin/env python3
"""Synthetic static text vs motion check; not a substitute for visual/device QA."""
from pathlib import Path
import json, re, subprocess, tempfile

app = Path(__file__).resolve().parents[1] / 'build/Hot Take.app/Contents/MacOS/Hot Take'
def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True)
with tempfile.TemporaryDirectory(prefix='relaytake-static-') as folder:
    folder = Path(folder)
    svg = folder/'screen.svg'
    lines = ''.join(f'<text x="80" y="{100+i*36}" font-family="monospace" font-size="24" fill="#222222">{i+1:02}  const recording = await captureScreen(); // Keep text readable</text>' for i in range(24))
    svg.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080"><rect width="1920" height="1080" fill="white"/>{lines}</svg>')
    png = folder/'screen.png'
    run('sips','-s','format','png',svg,'--out',png)
    static = folder/'static.mp4'; motion = folder/'motion.mp4'
    run('ffmpeg','-v','error','-loop','1','-framerate','24','-i',png,'-t','6','-c:v','libx264','-crf','0','-pix_fmt','yuv420p',static)
    run('ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=1920x1080:rate=24','-t','6','-c:v','libx264','-crf','0',motion)
    sizes = {}
    for name, source in [('static',static),('motion',motion)]:
        output = folder/f'{name}-encoded.mp4'
        run(app,'--compress',source,output,'medium','--no-audio')
        run('ffmpeg','-v','error','-i',output,'-f','null','-')
        sizes[name] = output.stat().st_size
    # Compare equal-resolution decoded images, not compressed source sizes.
    result = run('ffmpeg','-i',folder/'static-encoded.mp4','-i',static,'-lavfi','ssim','-f','null','-')
    score = float(re.findall(r'All:([0-9.]+)', result.stderr)[-1])
    assert score > .98, score
    assert sizes['static'] < sizes['motion'] * .8, sizes
    # Fast-start MP4 places movie metadata before media data.
    data = (folder/'static-encoded.mp4').read_bytes()
    assert 0 < data.find(b'moov') < data.find(b'mdat')
    print(json.dumps({'bytes':sizes,'staticSSIM':score,'fastStart':True}))
