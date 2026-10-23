#!/usr/bin/env python3
"""Synthetic codec check. Requires ffmpeg/ffprobe and a built Hot Take.app. No user videos."""
from pathlib import Path
import hashlib, json, subprocess, tempfile

app = Path(__file__).resolve().parents[1] / 'build/Hot Take.app/Contents/MacOS/Hot Take'
def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True)
def probe(path):
    return json.loads(run('ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', path).stdout)
with tempfile.TemporaryDirectory(prefix='relaytake-compression-') as folder:
    folder = Path(folder)
    source = folder / 'source.mp4'
    run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=30',
        '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '4', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '16', '-c:a', 'aac', source)
    original_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    results = []
    for quality, width, height, fps, channels in [('small',1280,720,15,1),('medium',1920,1080,24,2),('large',1920,1080,30,2)]:
        output = folder / f'{quality}.mp4'
        run(app, '--compress', source, output, quality)
        info = probe(output); video = next(s for s in info['streams'] if s['codec_type']=='video'); audio = next(s for s in info['streams'] if s['codec_type']=='audio')
        assert (video['width'], video['height'], video['r_frame_rate']) == (width,height,f'{fps}/1'), video
        assert audio['codec_name']=='aac' and audio['channels']==channels
        assert abs(float(info['format']['duration'])-4)<.1
        assert output.stat().st_size < source.stat().st_size
        # Decode every frame and audio packet, not just container headers.
        run('ffmpeg','-v','error','-i',output,'-f','null','-')
        results.append({'preset':quality,'bytes':output.stat().st_size,'resolution':f'{width}x{height}','fps':fps})
    cut = folder/'cut.mp4'
    run(app,'--cut',source,cut,'1','2','small')
    cut_info = probe(cut)
    assert abs(float(cut_info['format']['duration'])-3)<.1
    assert next(s for s in cut_info['streams'] if s['codec_type']=='video')['width']==1280
    run('ffmpeg','-v','error','-i',cut,'-f','null','-')
    silent = folder/'silent.mp4'
    run(app,'--compress',source,silent,'small','--no-audio')
    assert all(s['codec_type']!='audio' for s in probe(silent)['streams'])
    rejected = subprocess.run([str(app),'--compress',str(source),str(source),'small'],capture_output=True)
    assert rejected.returncode!=0
    assert hashlib.sha256(source.read_bytes()).hexdigest()==original_hash
    print(json.dumps({'sourceBytes':source.stat().st_size,'presets':results,'editedCopy':'passed','silent':'passed','noOverwrite':'passed'}))
