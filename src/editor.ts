import {setupAudioEditor} from './audio-editor';
import {emptyAudio, type AudioEdit} from './audio-edit';
import {setupTextEditor} from './text-overlay-editor';
import type {TextOverlay} from './text-overlay';
import './style.css';
import './editor.css';
import {iconSvg} from './icons';
import {list, readBlob, type Recording} from './storage';
import {changeRange, length, timeLabel, type Segment} from './edit-model';
import {exportEdit, seek} from './edit-export';
import {CHANNEL} from './control';

document.querySelector('#editor')!.innerHTML =
  `<header><a class="brand" href="./index.html"><img class="brand-icon" src="./favicon.svg" alt="">Hot Take</a><div class="editor-actions"><a href="./index.html" class="back-link">Library</a><button id="save-copy" class="primary" disabled>Save copy</button></div></header><main class="editor-main"><h1 id="edit-title">Edit</h1><video id="edit-video" controls playsinline></video><fieldset id="edit-tools" disabled><legend class="sr-only">Editing controls</legend><div class="edit-toolbar"><button id="preview-edits">${iconSvg('play')} Preview edit</button><span id="edit-length"></span><button id="undo" class="icon-button" aria-label="Undo" title="Undo">${iconSvg('undo')}</button><button id="reset" class="icon-button" aria-label="Reset edits" title="Reset">${iconSvg('refresh')}</button></div><div class="timeline-wrap"><div id="timeline" aria-label="Kept and removed sections"></div><input id="range-start" class="range-handle" type="range" min="0" step="0.05" value="0" aria-label="Selection start"><input id="range-end" class="range-handle" type="range" min="0" step="0.05" aria-label="Selection end"></div><input id="scrub" type="range" min="0" step="0.05" value="0" aria-label="Playhead"><div class="range-controls"><label>From <input id="from" type="number" min="0" step="0.1" value="0" aria-label="Selection start in seconds"></label><button id="mark-in" class="icon-button" aria-label="Set start to playhead" title="Set start to playhead">${iconSvg('markIn')}</button><label>To <input id="to" type="number" min="0" step="0.1" aria-label="Selection end in seconds"></label><button id="mark-out" class="icon-button" aria-label="Set end to playhead" title="Set end to playhead">${iconSvg('markOut')}</button><button id="keep">${iconSvg('trim')} Trim to selection</button><button id="cut">${iconSvg('scissors')} Remove selection</button></div></fieldset><div class="save-progress" hidden id="saving"><progress id="export-progress" max="1" value="0"></progress><button id="cancel">Cancel</button></div><p id="edit-status" role="status" aria-live="polite"></p></main>`;
const el = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const video = el<HTMLVideoElement>('edit-video');
let original: Recording | undefined,
  total = 0,
  segments: Segment[] = [],
  history: {segments: Segment[]; texts: TextOverlay[]; audio: AudioEdit}[] = [],
  exporting = false,
  previewing = false,
  url = '';
let texts: TextOverlay[] = [];
const remember = () =>
  history.push({
    segments: segments.map((s) => ({...s})),
    texts: texts.map((t) => ({...t})),
    audio: audioEditor.get(),
  });
const textEditor = setupTextEditor(
  video,
  () => texts,
  remember,
  render,
  () => total,
  () => exporting || !original || audioEditor.busy,
);
let controller: AbortController | undefined;
const status = (message: string) => {
  el('edit-status').textContent = message;
};
const audioEditor = setupAudioEditor(
  video,
  () => segments,
  remember,
  render,
  status,
  () => exporting || !original,
);
function render() {
  audioEditor.render();
  el<HTMLFieldSetElement>('edit-tools').disabled = exporting || audioEditor.busy || !total;
  textEditor.render();
  const timeline = el('timeline');
  timeline.replaceChildren();
  let cursor = 0;
  for (const segment of segments) {
    if (segment.start > cursor) add(cursor, segment.start, true);
    add(segment.start, segment.end, false);
    cursor = segment.end;
  }
  if (cursor < total) add(cursor, total, true);
  function add(start: number, end: number, removed: boolean) {
    const block = document.createElement('span');
    block.style.width = `${(100 * (end - start)) / total}%`;
    block.className = removed ? 'removed' : 'kept';
    block.title = `${removed ? 'Removed' : 'Kept'} ${timeLabel(start)}–${timeLabel(end)}`;
    timeline.append(block);
  }
  const selection = document.createElement('span');
  selection.className = 'selection';
  const a = Number(el<HTMLInputElement>('from').value),
    b = Number(el<HTMLInputElement>('to').value);
  selection.style.left = `${(100 * Math.max(0, Math.min(a, total))) / total}%`;
  selection.style.width = `${(100 * Math.max(0, Math.min(b, total) - Math.max(0, a))) / total}%`;
  timeline.append(selection);
  el<HTMLInputElement>('range-start').value = String(a);
  el<HTMLInputElement>('range-end').value = String(b);
  el('edit-length').textContent = timeLabel(length(segments));
  el<HTMLButtonElement>('undo').disabled = !history.length;
  el<HTMLButtonElement>('reset').disabled = !history.length;
  el<HTMLButtonElement>('save-copy').disabled = !history.length || exporting || audioEditor.busy;
}
function edit(keep: boolean) {
  try {
    const next = changeRange(
      segments,
      Number(el<HTMLInputElement>('from').value),
      Number(el<HTMLInputElement>('to').value),
      keep,
    );
    if (JSON.stringify(next) === JSON.stringify(segments)) return;
    video.pause();
    previewing = false;
    remember();
    segments = next;
    status('');
    render();
  } catch (error) {
    status((error as Error).message);
  }
}
el('cut').onclick = () => edit(false);
el('keep').onclick = () => edit(true);
el('undo').onclick = () => {
  const previous = history.pop();
  if (previous) {
    segments = previous.segments;
    texts = previous.texts;
    audioEditor.set(previous.audio);
    video.pause();
    previewing = false;
    render();
  }
};
el('reset').onclick = () => {
  segments = [{start: 0, end: total}];
  texts = [];
  audioEditor.set(emptyAudio());
  history = [];
  video.pause();
  previewing = false;
  render();
};
for (const name of ['from', 'to']) el(name).oninput = render;
for (const [handle, field] of [
  ['range-start', 'from'],
  ['range-end', 'to'],
])
  el<HTMLInputElement>(handle).oninput = () => {
    const value = Number(el<HTMLInputElement>(handle).value);
    el<HTMLInputElement>(field).value = String(
      handle === 'range-start'
        ? Math.min(value, Number(el<HTMLInputElement>('to').value) - 0.05)
        : Math.max(value, Number(el<HTMLInputElement>('from').value) + 0.05),
    );
    render();
  };
el('mark-in').onclick = () => {
  el<HTMLInputElement>('from').value = video.currentTime.toFixed(1);
  render();
};
el('mark-out').onclick = () => {
  el<HTMLInputElement>('to').value = video.currentTime.toFixed(1);
  render();
};
el<HTMLInputElement>('scrub').oninput = () => {
  previewing = false;
  video.currentTime = Number(el<HTMLInputElement>('scrub').value);
};
video.addEventListener('timeupdate', () => {
  el<HTMLInputElement>('scrub').value = String(video.currentTime);
  if (previewing && !audioEditor.busy && !video.seeking) {
    const next = segments.find((s) => video.currentTime < s.end - 0.015);
    if (!next) {
      video.pause();
      previewing = false;
    } else if (video.currentTime < next.start) video.currentTime = next.start;
  }
});
el('preview-edits').onclick = () => {
  void (async () => {
    video.pause();
    await seek(video, segments[0].start, new AbortController().signal);
    previewing = true;
    await video.play();
  })().catch(() => status('Could not preview this recording.'));
};
el('save-copy').onclick = () => {
  void (async () => {
    if (!original || exporting || audioEditor.busy || !history.length) return;
    video.pause();
    previewing = false;
    exporting = true;
    controller = new AbortController();
    el<HTMLFieldSetElement>('edit-tools').disabled = true;
    el<HTMLButtonElement>('save-copy').disabled = true;
    video.controls = false;
    el('saving').hidden = false;
    status('Saving in real time. Keep this tab visible.');
    try {
      const id = await exportEdit(
        original,
        segments.map((s) => ({...s})),
        controller.signal,
        (fraction) => {
          el<HTMLProgressElement>('export-progress').value = fraction;
        },
        texts.map((t) => ({...t})),
        audioEditor.get(),
      );
      history = [];
      const channel = new BroadcastChannel(CHANNEL);
      channel.postMessage({type: 'library-changed'});
      channel.close();
      status('Copy saved.');
      const link = document.createElement('a');
      link.href = `./index.html?view=library&preview=${encodeURIComponent(id)}`;
      link.textContent = 'Open copy';
      link.className = 'saved-copy';
      el('edit-status').append(' ', link);
    } catch (error) {
      status(controller.signal.aborted ? 'Save canceled.' : (error as Error).message);
    } finally {
      exporting = false;
      el<HTMLFieldSetElement>('edit-tools').disabled = false;
      video.controls = true;
      el('saving').hidden = true;
      render();
    }
  })();
};
el('cancel').onclick = () => controller?.abort();
window.addEventListener('beforeunload', (event) => {
  if (exporting || audioEditor.busy || history.length) event.preventDefault();
});
window.addEventListener('pagehide', () => {
  controller?.abort();
  if (url) URL.revokeObjectURL(url);
});
async function load() {
  const id = new URLSearchParams(location.search).get('id');
  original = (await list()).find((r) => r.id === id);
  if (!original || original.status !== 'ready')
    throw new Error('This recording is unavailable for editing.');
  el('edit-title').textContent = original.title;
  url = URL.createObjectURL(await readBlob(original));
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Video could not be loaded.')), 15000);
    video.onloadeddata = () => {
      clearTimeout(timer);
      resolve();
    };
    video.onerror = () => {
      clearTimeout(timer);
      reject(new Error('Video could not be loaded.'));
    };
    video.src = url;
  });
  total = Number.isFinite(video.duration) ? video.duration : original.duration / 1000;
  if (!Number.isFinite(total) || total < 0.1)
    throw new Error('This recording has no usable duration.');
  segments = [{start: 0, end: total}];
  el<HTMLInputElement>('to').value = total.toFixed(2);
  for (const id of ['from', 'to', 'scrub', 'range-start', 'range-end'])
    el<HTMLInputElement>(id).max = String(total);
  el<HTMLFieldSetElement>('edit-tools').disabled = false;
  render();
}
void load().catch((error) => status((error as Error).message));
