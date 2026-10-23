#!/usr/bin/env python3
"""Synthetic format export checks. Requires a built app and ffmpeg/ffprobe."""
from pathlib import Path
import hashlib, json, subprocess, tempfile

app = Path(__file__).resolve().parents[1] / 'build/Hot Take.app/Contents/MacOS/Hot Take'
def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True)
def probe(path):
    return json.loads(run('ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', path).stdout)
with tempfile.TemporaryDirectory(prefix='relaytake-formats-') as folder:
    folder = Path(folder)
    source = folder / 'source.mp4'
    run('ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24',
        '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '2',
        '-c:v', 'libx264', '-c:a', 'aac', source)
    original = hashlib.sha256(source.read_bytes()).hexdigest()
    for extension, video_codec, audio_codec in [('mp4','h264','aac'), ('mov','h264','aac'), ('webm','vp9','opus')]:
        output = folder / ('export.' + extension)
        run(app, '--export', source, output, extension)
        info = probe(output)
        video = next(s for s in info['streams'] if s['codec_type'] == 'video')
        audio = next(s for s in info['streams'] if s['codec_type'] == 'audio')
        assert video['codec_name'] == video_codec and audio['codec_name'] == audio_codec, info
        assert abs(float(info['format']['duration']) - 2) < .15, info
        assert video['width'] == 640 and video['height'] == 360
        if extension == 'mov': assert info['format']['tags']['major_brand'].strip() == 'qt'
        if extension == 'mp4': assert info['format']['tags']['major_brand'].strip() != 'qt'
        if extension == 'webm': assert 'webm' in info['format']['format_name']
        run('ffmpeg', '-v', 'error', '-i', output, '-f', 'null', '-')
        silent = folder / ('silent.' + extension)
        run(app, '--export', source, silent, extension, '--no-audio')
        assert all(s['codec_type'] != 'audio' for s in probe(silent)['streams'])
        print(extension + ': container, codecs, duration, full decode and silent export passed')
    rejected = subprocess.run([str(app), '--export', str(source), str(source), 'mp4'], capture_output=True)
    assert rejected.returncode != 0
    assert hashlib.sha256(source.read_bytes()).hexdigest() == original
    assert not list(folder.glob('.relaytake-export-*'))
    print('Original preserved; temporary files cleaned up.')
