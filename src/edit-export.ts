import {emptyAudio, playClips, type AudioEdit} from './audio-edit';
import {drawText, type TextOverlay} from './text-overlay';
import {append, save, finalize, remove, readBlob, type Recording} from './storage';
import {supportedMime} from './capture';
import {length, type Segment} from './edit-model';

const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 16));
async function waitFor(check: () => boolean, signal: AbortSignal, timeout = 15000) {
  const until = performance.now() + timeout;
  while (!check()) {
    signal.throwIfAborted();
    if (performance.now() > until)
      throw new Error('Video could not be decoded. Try a shorter selection.');
    await tick();
  }
  signal.throwIfAborted();
}
export async function seek(video: HTMLVideoElement, time: number, signal: AbortSignal) {
  if (Math.abs(video.currentTime - time) < 0.015 && video.readyState >= 2) return;
  video.currentTime = time;
  await waitFor(() => !video.seeking && video.readyState >= 2, signal);
}
/** Local, real-time re-encoding. Only kept segments enter the encoder. */
export async function exportEdit(
  original: Recording,
  segments: Segment[],
  signal: AbortSignal,
  progress: (fraction: number) => void,
  texts: TextOverlay[] = [],
  mix: AudioEdit = emptyAudio(),
): Promise<string> {
  const id = crypto.randomUUID();
  const video = document.createElement('video');
  video.playsInline = true;
  video.preload = 'auto';
  const audio = new AudioContext(); // Construct/resume in the Save click's activation.
  const resumed = audio.resume();
  let release: (() => void) | undefined;
  let stopMix = () => {};
  let url = '',
    stream: MediaStream | undefined,
    recorder: MediaRecorder | undefined;
  let writes = Promise.resolve(),
    queued = 0,
    failure: Error | undefined,
    created = false,
    completed = false;
  const check = () => {
    signal.throwIfAborted();
    if (failure) throw failure;
    if (document.hidden)
      throw new Error(
        'Saving stopped because this tab was hidden. Keep the editor visible and try again.',
      );
  };
  try {
    const locked = await new Promise<boolean>((resolve, reject) => {
      void navigator.locks
        .request('relaytake-recorder', {ifAvailable: true}, async (lock) => {
          if (!lock) {
            resolve(false);
            return;
          }
          await new Promise<void>((unlock) => {
            release = unlock;
            resolve(true);
          });
        })
        .catch(reject);
    });
    if (!locked) throw new Error('Stop the active recording or save before exporting.');
    await resumed;
    url = URL.createObjectURL(await readBlob(original));
    video.src = url;
    await waitFor(() => video.readyState >= 2, signal);
    check();
    const canvas = document.createElement('canvas');
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext('2d')!;
    const draw = () => {
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
      drawText(ctx, texts, video.currentTime, canvas.width, canvas.height);
    };
    const source = audio.createMediaElementSource(video);
    const destination = audio.createMediaStreamDestination();
    const originalGain = audio.createGain();
    originalGain.gain.value = mix.original;
    source.connect(originalGain).connect(destination);
    // Deliberately do not connect to speakers while exporting.
    stream = canvas.captureStream(30);
    destination.stream.getAudioTracks().forEach((track) => stream!.addTrack(track));
    const mime = supportedMime();
    if (!mime) throw new Error('This browser cannot save the edited video.');
    recorder = new MediaRecorder(stream, {
      mimeType: mime,
      videoBitsPerSecond: 4000000,
      audioBitsPerSecond: 128000,
    });
    recorder.ondataavailable = (event) => {
      if (!event.data.size) return;
      queued += event.data.size;
      if (queued > 32 * 1024 * 1024) {
        failure = new Error('Storage could not keep up.');
        return;
      }
      writes = writes
        .then(() => append(id, event.data))
        .catch(() => {
          failure = new Error('Not enough local storage to save this copy.');
        })
        .finally(() => {
          queued -= event.data.size;
        });
    };
    recorder.onerror = () => {
      failure = new Error('Video encoding failed.');
    };
    await save({
      id,
      title: `${original.title} (edited)`,
      created: Date.now(),
      mime: recorder.mimeType,
      size: 0,
      chunks: 0,
      duration: 0,
      status: 'recording',
    });
    created = true;
    let kept = 0;
    const total = length(segments);
    for (const segment of segments) {
      check();
      await seek(video, segment.start, signal);
      draw();
      await video.play();
      if (recorder.state === 'inactive') recorder.start(1000);
      else recorder.resume();
      stopMix = playClips(audio, destination, mix, kept, segment.end - segment.start);
      let lastTime = video.currentTime,
        lastAdvance = performance.now();
      while (video.currentTime < segment.end && !video.ended) {
        check();
        draw();
        if (video.currentTime !== lastTime) {
          lastTime = video.currentTime;
          lastAdvance = performance.now();
        }
        if (performance.now() - lastAdvance > 10000)
          throw new Error('Playback stalled while saving.');
        progress(Math.min(0.99, (kept + Math.max(0, video.currentTime - segment.start)) / total));
        await tick();
      }
      stopMix();
      recorder.pause();
      video.pause();
      if (video.ended && video.currentTime < segment.end - 0.25)
        throw new Error('The selected range extends beyond the playable video.');
      kept += segment.end - segment.start;
    }
    await new Promise<void>((resolve) => {
      recorder!.onstop = () => resolve();
      recorder!.stop();
    });
    await writes;
    check();
    await finalize(id, total * 1000);
    completed = true;
    progress(1);
    return id;
  } finally {
    stopMix();
    video.pause();
    if (recorder && recorder.state !== 'inactive')
      await new Promise<void>((resolve) => {
        recorder!.onstop = () => resolve();
        recorder!.stop();
      });
    await writes;
    stream?.getTracks().forEach((track) => track.stop());
    await audio.close();
    video.removeAttribute('src');
    video.load();
    if (url) URL.revokeObjectURL(url);
    // Only the newly generated, incomplete copy is removed. The original is never mutated.
    try {
      if (created && !completed) await remove(id);
    } finally {
      release?.();
    }
  }
}
