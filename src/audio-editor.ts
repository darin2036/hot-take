import {copyAudio, emptyAudio, editedTime, playClips, type AudioEdit} from './audio-edit';
import {length, type Segment} from './edit-model';
import {seek} from './edit-export';
import {iconSvg} from './icons';
export function setupAudioEditor(
  video: HTMLVideoElement,
  segments: () => Segment[],
  remember: () => void,
  changed: () => void,
  status: (s: string) => void,
  locked: () => boolean,
) {
  let state = emptyAudio(),
    busy = false,
    context: AudioContext | undefined,
    stopMix = () => {},
    syncKey = '',
    abort: AbortController | undefined,
    activeMic: MediaStream | undefined;
  const panel = document.createElement('div');
  panel.className = 'audio-tools';
  panel.innerHTML = `<button id="add-audio">Add audio</button><input id="audio-file" type="file" accept="audio/*" hidden><button id="record-voice">Record voiceover</button><label>Original audio <input id="original-volume" aria-label="Original audio volume" type="range" min="0" max="1" step="0.05" value="1"></label><div id="audio-clips"></div>`;
  document.querySelector('#edit-tools')!.append(panel);
  const recording = document.createElement('div');
  recording.className = 'voice-controls';
  recording.hidden = true;
  recording.innerHTML =
    '<span role="status">Recording voiceover…</span><button id="voice-stop">Stop</button><button id="voice-cancel">Cancel</button>';
  panel.parentElement!.after(recording);
  const el = <T extends HTMLElement>(id: string) => panel.querySelector<T>('#' + id)!;
  const audio = () => {
    context ??= new AudioContext();
    void context.resume();
    return context;
  };
  const halt = () => {
    stopMix();
    stopMix = () => {};
    syncKey = '';
  };
  function render() {
    halt();
    if (!busy) video.muted = false;
    video.volume = state.original;
    el<HTMLInputElement>('original-volume').value = String(state.original);
    const clips = el('audio-clips');
    clips.replaceChildren();
    for (const clip of state.clips) {
      const row = document.createElement('div');
      row.className = 'audio-clip';
      const name = document.createElement('span');
      name.textContent = clip.name;
      name.title = clip.name;
      const startLabel = document.createElement('label');
      startLabel.textContent = 'Starts at';
      const start = document.createElement('input');
      start.type = 'number';
      start.min = '0';
      start.step = '.1';
      start.value = String(clip.start);
      start.setAttribute('aria-label', `${clip.kind} audio start in edited video`);
      startLabel.append(start);
      start.onchange = () => {
        const value = Number(start.value);
        if (!Number.isFinite(value) || value < 0 || value >= length(segments())) {
          start.value = String(clip.start);
          status('Choose a start time inside the edited video.');
          return;
        }
        remember();
        clip.start = value;
        changed();
      };
      const volume = document.createElement('input');
      volume.type = 'range';
      volume.min = '0';
      volume.max = '1';
      volume.step = '.05';
      volume.value = String(clip.volume);
      volume.setAttribute('aria-label', `${clip.kind} audio volume`);
      volume.onchange = () => {
        remember();
        clip.volume = Number(volume.value);
        changed();
      };
      const remove = document.createElement('button');
      remove.innerHTML = iconSvg('trash');
      remove.className = 'icon-button';
      remove.setAttribute('aria-label', `Remove ${clip.kind} audio`);
      remove.onclick = () => {
        remember();
        state.clips = state.clips.filter((c) => c !== clip);
        changed();
      };
      row.append(name, startLabel, volume, remove);
      clips.append(row);
    }
  }
  async function importFile(file: File) {
    if (locked() || busy) return;
    busy = true;
    video.pause();
    changed();
    try {
      if (file.size > 100 * 1024 * 1024)
        throw new Error('Choose an audio file smaller than 100 MB.');
      const buffer = await audio().decodeAudioData(await file.arrayBuffer());
      if (buffer.length * buffer.numberOfChannels * 4 > 128 * 1024 * 1024)
        throw new Error('Choose a shorter audio file.');
      remember();
      state.clips = state.clips.filter((c) => c.kind !== 'file');
      state.clips.push({kind: 'file', name: file.name, buffer, start: 0, volume: 0.5});
      status('');
    } catch (error) {
      status(error instanceof Error ? error.message : 'Could not read this audio file.');
    } finally {
      busy = false;
      changed();
    }
  }
  el('add-audio').onclick = () => {
    audio();
    el<HTMLInputElement>('audio-file').click();
  };
  el<HTMLInputElement>('audio-file').onchange = () => {
    const file = el<HTMLInputElement>('audio-file').files?.[0];
    if (file) void importFile(file);
    el<HTMLInputElement>('audio-file').value = '';
  };
  panel.ondragover = (e) => {
    e.preventDefault();
  };
  panel.ondrop = (e) => {
    e.preventDefault();
    const file = e.dataTransfer?.files[0];
    if (file) void importFile(file);
  };
  el<HTMLInputElement>('original-volume').onchange = () => {
    remember();
    state.original = Number(el<HTMLInputElement>('original-volume').value);
    changed();
  };
  el('record-voice').onclick = () => {
    void record();
  };
  async function record() {
    if (busy || locked()) return;
    busy = true;
    video.pause();
    halt();
    audio();
    abort = new AbortController();
    changed();
    video.controls = false;
    video.muted = true;
    const previousRate = video.playbackRate;
    video.playbackRate = 1;
    let cancel = false,
      finishEarly = false,
      mic: MediaStream | undefined,
      recorder: MediaRecorder | undefined;
    const chunks: Blob[] = [];
    recording.hidden = false;
    recording.querySelector('span')!.textContent = 'Allow microphone access…';
    (recording.querySelector('#voice-stop') as HTMLButtonElement).onclick = () => {
      finishEarly = true;
    };
    (recording.querySelector('#voice-cancel') as HTMLButtonElement).onclick = () => {
      cancel = true;
      abort?.abort();
    };
    try {
      await navigator.locks.request('relaytake-recorder', {ifAvailable: true}, async (lock) => {
        if (!lock) throw new Error('Stop the active recording or export first.');
        mic = await navigator.mediaDevices.getUserMedia({
          audio: {echoCancellation: true, noiseSuppression: true},
        });
        activeMic = mic;
        abort!.signal.throwIfAborted();
        recorder = new MediaRecorder(mic);
        let failure = false;
        recorder.onerror = () => {
          failure = true;
        };
        mic.getAudioTracks().forEach(
          (t) =>
            (t.onended = () => {
              failure = true;
            }),
        );
        recorder.ondataavailable = (e) => {
          if (e.data.size) chunks.push(e.data);
        };
        recording.querySelector('span')!.textContent = 'Recording voiceover…';
        status('');
        for (const segment of segments()) {
          if (finishEarly) break;
          await seek(video, segment.start, abort!.signal);
          await video.play();
          if (recorder.state === 'inactive') recorder.start(1000);
          else recorder.resume();
          let last = video.currentTime,
            advanced = performance.now();
          while (video.currentTime < segment.end && !video.ended && !finishEarly) {
            abort!.signal.throwIfAborted();
            if (failure) throw new Error('Microphone recording stopped. Try again.');
            if (document.hidden)
              throw new Error('Keep this tab visible while recording voiceover.');
            if (last !== video.currentTime) {
              last = video.currentTime;
              advanced = performance.now();
            }
            if (performance.now() - advanced > 10000)
              throw new Error('Video playback stalled. Try again.');
            await new Promise((r) => setTimeout(r, 16));
          }
          recorder.pause();
          video.pause();
        }
        if (recorder.state !== 'inactive')
          await new Promise<void>((r) => {
            recorder!.onstop = () => r();
            recorder!.stop();
          });
        abort!.signal.throwIfAborted();
        if (chunks.length) {
          const buffer = await audio().decodeAudioData(await new Blob(chunks).arrayBuffer());
          abort!.signal.throwIfAborted();
          remember();
          state.clips = state.clips.filter((c) => c.kind !== 'voice');
          state.clips.push({kind: 'voice', name: 'Voiceover', buffer, start: 0, volume: 1});
          state.original = 0;
          status('Voiceover added.');
        }
      });
    } catch (error) {
      status(
        cancel
          ? 'Voiceover canceled.'
          : error instanceof Error
            ? error.message
            : 'Could not record voiceover.',
      );
    } finally {
      if (recorder && recorder.state !== 'inactive') recorder.stop();
      mic?.getTracks().forEach((t) => t.stop());
      activeMic = undefined;
      video.pause();
      video.muted = false;
      video.controls = true;
      video.playbackRate = previousRate;
      busy = false;
      abort = undefined;
      recording.hidden = true;
      changed();
    }
  }
  video.addEventListener('volumechange', () => {
    if (busy || locked()) return;
    const volume = video.muted ? 0 : video.volume;
    if (volume !== state.original) {
      remember();
      state.original = volume;
      changed();
    }
  });
  let frame = 0,
    lastTime = 0;
  function tick() {
    if (
      !busy &&
      !locked() &&
      !video.paused &&
      !video.seeking &&
      state.clips.length &&
      segments().some((s) => video.currentTime >= s.start && video.currentTime < s.end)
    ) {
      const time = editedTime(segments(), video.currentTime),
        key = JSON.stringify([
          video.playbackRate,
          state.clips.map((c) => [c.kind, c.start, c.volume]),
        ]);
      if (syncKey !== key || Math.abs(time - lastTime) > 0.15) {
        halt();
        const ctx = audio();
        stopMix = playClips(
          ctx,
          ctx.destination,
          state,
          time,
          length(segments()) - time,
          video.playbackRate,
        );
        syncKey = key;
      }
      lastTime = time;
    } else halt();
    frame = requestAnimationFrame(tick);
  }
  tick();
  video.addEventListener('seeking', halt);
  video.addEventListener('pause', halt);
  video.addEventListener('play', () => {
    audio();
  });
  window.addEventListener(
    'pagehide',
    () => {
      abort?.abort();
      activeMic?.getTracks().forEach((t) => t.stop());
      halt();
      cancelAnimationFrame(frame);
      void context?.close();
    },
    {once: true},
  );
  return {
    render,
    get busy() {
      return busy;
    },
    get: () => copyAudio(state),
    set: (value: AudioEdit) => {
      state = copyAudio(value);
      render();
    },
  };
}
