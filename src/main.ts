import {CountdownSound} from './countdown-sound';
import {FloatingControls} from './floating-controls';
import {ThumbnailQueue} from './thumbnails';
import {bindSettingsMenu} from './settings-menu';
import {bindInputs} from './preferences';
import {iconSvg, iconLabel, type IconName} from './icons';
import './style.css';
import {ActiveClock, bytes, duration, filename} from './core';
import {acquire, supportedMime, type Capture} from './capture';
import * as storage from './storage';
import {CHANNEL, isRequest, type Snapshot} from './control';
import {openSurface} from './navigation';
const params = new URLSearchParams(location.search);
const view = params.get('view') || 'library';
document.body.classList.add(`${view}-view`);

const root = document.querySelector<HTMLDivElement>('#app')!;
root.innerHTML = `<header><a class="brand" href="./"><img class="brand-icon" src="./favicon.svg" alt="">Hot Take</a><div id="header-actions"></div></header>
<main><section class="intro"></section>
<div class="workspace"><section class="studio" aria-labelledby="studio-title"><div class="section-heading"><h2 id="studio-title">Record</h2><span id="state" class="pill">Ready</span></div>
<div class="stage"><video id="monitor" muted autoplay playsinline></video><div id="placeholder"><div class="screen-icon">${iconSvg('monitor')}</div></div><span id="countdown" role="status" aria-live="assertive" hidden></span><span id="timer" class="timer">00:00</span></div>
<div class="setup"><label class="title-label"><span class="sr-only">Recording title</span><input id="title" maxlength="120" placeholder="Untitled recording"></label><fieldset id="settings"><legend class="sr-only">Recording options</legend><div class="options"><label><input id="mic" type="checkbox"><span>Microphone</span></label><label><input id="camera" type="checkbox"><span>Camera</span></label><label><input id="audio" type="checkbox"><span>Source audio</span></label></div><div class="select-row"><label>Quality<select id="quality"><option value="high">1080p</option><option value="low">720p</option></select></label></div></fieldset>
<div class="actions"><button id="start" class="primary" aria-label="Start recording">${iconSvg('circle')} Record</button><button id="pause" hidden>${iconSvg('pause')} Pause</button><button id="restart" title="Restart and discard current take" hidden>${iconSvg('refresh')} Restart</button><button id="float" class="icon-button" aria-label="Float recording controls" title="Float controls" hidden>${iconSvg('external')}</button><button id="stop" class="danger" aria-label="Stop & save" hidden>${iconSvg('square')} Stop</button></div><p id="status" role="status" aria-live="polite"></p></div></section></div>
<section class="library" id="library" aria-label="Recordings"><h1 class="sr-only">Recordings</h1><span id="count" hidden></span><button id="refresh" class="icon-button" aria-label="Refresh library" title="Refresh">${iconSvg('refresh')}</button><div id="recordings"></div></section></main>
<dialog id="preview"><div class="section-heading"><h2 id="preview-title">Preview</h2><button id="close-preview" aria-label="Close preview">${iconSvg('close')}</button></div><video id="playback" controls playsinline></video><p id="recovery-warning" class="fine" hidden>Recovered recording: playback may be incomplete.</p></dialog>`;
const el = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const start = el<HTMLButtonElement>('start'),
  pause = el<HTMLButtonElement>('pause'),
  stop = el<HTMLButtonElement>('stop');
const status = (message: string) => {
  (el('library-status') || el('status')).textContent = message;
};
let capture: Capture | undefined,
  recorder: MediaRecorder | undefined,
  clock = new ActiveClock(),
  id = '',
  pending = Promise.resolve(),
  queued = 0,
  failed = false,
  stopping = false,
  busy = false,
  release: (() => void) | undefined,
  warningShown = false;
let objectURL: string | undefined;
let countdown = 0,
  countdownToken = 0,
  restarting = false;
const countdownSound = new CountdownSound();
const floating = new FloatingControls(
  () => snapshot(),
  (action) => {
    if (action === 'restart') restartTake();
    else if (action === 'stop') end();
    else pause.click();
  },
);
const restart = el<HTMLButtonElement>('restart'),
  float = el<HTMLButtonElement>('float');
float.onclick = () => {
  void floating
    .open()
    .catch(() => status('Floating controls are unavailable. Use this recorder window.'));
};
restart.onclick = restartTake;
const monitor = el<HTMLVideoElement>('monitor');
const owner = crypto.randomUUID();
const channel = new BroadcastChannel(CHANNEL);
function snapshot(): Snapshot {
  return {
    owner,
    countdown,
    state: stopping
      ? 'saving'
      : countdown
        ? 'countdown'
        : recorder?.state === 'paused'
          ? 'paused'
          : recorder?.state === 'recording'
            ? 'recording'
            : 'starting',
    elapsed: recorder ? clock.elapsed : 0,
    title: el<HTMLInputElement>('title').value.trim() || 'Untitled take',
  };
}
channel.onmessage = (event) => {
  const message = event.data;
  if (message?.type === 'configure' && !busy) {
    for (const name of ['mic', 'camera', 'audio']) {
      if (typeof message[name] === 'boolean') el<HTMLInputElement>(name).checked = message[name];
    }
    return;
  }
  if (message?.type === 'library-changed') {
    void refresh();
    return;
  }
  if (!isRequest(message) || !busy || (message.command !== 'status' && message.owner !== owner))
    return;
  if (message.command === 'pause' && recorder?.state === 'recording' && !stopping) pause.click();
  if (message.command === 'resume' && recorder?.state === 'paused' && !stopping) pause.click();
  // Acknowledge before asynchronous finalization can release ownership.
  if (message.command === 'stop' && recorder && !stopping) end();
  if (message.command === 'restart') restartTake();
  channel.postMessage({version: 1, requestId: message.requestId, snapshot: snapshot()});
};
bindInputs(params, () => !busy);
const settingsMenu = document.createElement('details');
settingsMenu.className = 'settings-menu';
settingsMenu.innerHTML = `<summary aria-label="Recording settings" title="Settings">${iconSvg('menu')}</summary><div class="settings-panel"></div>`;
settingsMenu.querySelector('.settings-panel')!.append(el('settings'));
el('header-actions').append(settingsMenu);
bindSettingsMenu();

if (view === 'recorder') {
  document.title = 'Hot Take · Recorder';
  iconLabel(start, 'circle', 'Record');
  start.setAttribute('aria-label', 'Choose screen & record');
  el('studio-title').textContent = 'Record';
  const link = document.createElement('button');
  link.innerHTML = iconSvg('library');
  link.setAttribute('aria-label', 'Open library');
  link.title = 'Library';
  link.className = 'icon-button';
  link.onclick = () => {
    void openSurface('library');
  };
  el('header-actions').append(link);
  const saved = document.createElement('button');
  saved.id = 'saved-take';
  iconLabel(saved, 'play', 'Preview saved take');
  saved.hidden = true;
  saved.onclick = () => {
    void openSurface('library', new URLSearchParams({preview: id}));
  };
  el('status').after(saved);
}
if (view === 'library') {
  document.title = 'Hot Take · Your library';
  const intro = document.querySelector('.intro')!;
  const create = document.createElement('button');
  create.className = 'primary';
  iconLabel(create, 'circle', 'Record');
  create.setAttribute('aria-label', 'New recording');
  create.onclick = () => {
    void openSurface('recorder');
  };
  el('header-actions').append(el('refresh'), create);
  const feedback = document.createElement('p');
  feedback.id = 'library-status';
  feedback.setAttribute('role', 'status');
  intro.append(feedback);
}
document.querySelector<HTMLAnchorElement>('.brand')!.onclick = (event) => {
  if (view === 'recorder') {
    event.preventDefault();
    void openSurface('library');
  }
};
async function previewRecording(row: storage.Recording) {
  if (objectURL) URL.revokeObjectURL(objectURL);
  objectURL = URL.createObjectURL(await storage.readBlob(row));
  el<HTMLVideoElement>('playback').src = objectURL;
  el('preview-title').textContent = row.title;
  el('recovery-warning').hidden = row.status !== 'interrupted';
  el<HTMLDialogElement>('preview').showModal();
}

function controls(active: boolean) {
  start.hidden = active;
  start.disabled = busy;
  pause.hidden = !active;
  stop.hidden = !active;
  restart.hidden = !active;
  float.hidden = !active;
  restart.disabled = countdown > 0 || stopping;
  pause.disabled = countdown > 0 || stopping;
  el<HTMLFieldSetElement>('settings').disabled = busy;
  el<HTMLInputElement>('title').disabled = busy;
  el('placeholder').hidden = active;
  monitor.hidden = !active;
}
function end() {
  if (stopping) return;
  countdownSound.stop();
  restarting = false;
  stopping = true;
  countdownToken++;
  countdown = 0;
  el('countdown').hidden = true;
  pause.disabled = true;
  restart.disabled = true;
  stop.disabled = true;
  el('state').textContent = 'Saving…';
  if (recorder && recorder.state !== 'inactive') {
    clock.pause();
    recorder.stop();
  } else if (recorder) {
    void finish();
  }
}
function restartTake() {
  if (!recorder || stopping || countdown || !['recording', 'paused'].includes(recorder.state))
    return;
  restarting = true;
  stopping = true;
  clock.pause();
  pause.disabled = true;
  restart.disabled = true;
  stop.disabled = true;
  el('state').textContent = 'Restarting…';
  recorder.stop();
}
async function beginTake() {
  const mime = supportedMime();
  if (!mime || !capture) throw new Error('Recording source is unavailable.');
  const low = el<HTMLSelectElement>('quality').value === 'low';
  recorder = new MediaRecorder(capture.stream, {
    mimeType: mime,
    videoBitsPerSecond: low ? 2000000 : 4000000,
    audioBitsPerSecond: 128000,
  });
  id = crypto.randomUUID();
  await storage.save({
    id,
    title: el<HTMLInputElement>('title').value.trim() || 'Untitled take',
    created: Date.now(),
    mime: recorder.mimeType,
    size: 0,
    chunks: 0,
    duration: 0,
    status: 'recording',
  });
  clock = new ActiveClock();
  pending = Promise.resolve();
  queued = 0;
  failed = false;
  stopping = false;
  warningShown = false;
  const takeId = id;
  recorder.ondataavailable = (event) => {
    if (!event.data.size || failed) return;
    queued += event.data.size;
    if (queued > 32 * 1024 * 1024) {
      failed = true;
      status('Storage could not keep up. Stopping with committed bytes preserved.');
      end();
      return;
    }
    pending = pending
      .then(() => storage.append(takeId, event.data))
      .catch(() => {
        failed = true;
        end();
      })
      .finally(() => {
        queued -= event.data.size;
      });
  };
  recorder.onstop = () => {
    void finish();
  };
  recorder.onerror = () => {
    failed = true;
    end();
  };
  const token = ++countdownToken;
  countdown = 3;
  stop.disabled = false;
  controls(true);
  el('state').textContent = 'Get ready';
  el('countdown').hidden = false;
  for (let n = 3; n > 0; n--) {
    if (token !== countdownToken) return;
    countdown = n;
    el('countdown').textContent = String(n);
    countdownSound.ding(n === 1);
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  if (token !== countdownToken) return;
  countdown = 0;
  el('countdown').hidden = true;
  recorder.start(1000);
  clock.resume();
  controls(true);
  el('state').textContent = 'Recording';
  iconLabel(pause, 'pause', 'Pause');
  status(capture.warnings.join(' '));
}
async function finish() {
  await pending;
  if (restarting && !failed) {
    restarting = false;
    try {
      await storage.remove(id);
      await beginTake();
      return;
    } catch (error) {
      failed = true;
      status(error instanceof Error ? error.message : 'Could not restart recording.');
    }
  }
  countdownSound.close();
  capture?.dispose();
  capture = undefined;
  try {
    if (recorder?.state === 'inactive' && clock.elapsed === 0) await storage.remove(id);
    else await storage.finalize(id, clock.elapsed, failed);
    status(
      failed
        ? 'Recording interrupted. Committed bytes are in your library; playback may be incomplete.'
        : '',
    );
  } catch {
    status('Could not finalize metadata. Refresh to recover committed bytes.');
  }
  recorder = undefined;
  busy = false;
  release?.();
  release = undefined;
  controls(false);
  pause.disabled = false;
  stop.disabled = false;
  stopping = false;
  floating.close();
  el('state').textContent = failed ? 'Interrupted' : 'Saved';
  if (el('saved-take')) el('saved-take').hidden = clock.elapsed === 0;
  channel.postMessage({type: 'library-changed'});
  await refresh();
}
start.addEventListener('click', async () => {
  if (busy) return;
  if (!navigator.mediaDevices?.getDisplayMedia || !window.MediaRecorder || !navigator.locks) {
    status('Use a desktop browser on HTTPS or localhost to record.');
    return;
  }
  countdownSound.unlock();
  busy = true;
  if (el('saved-take')) el('saved-take').hidden = true;
  controls(false);
  status('Choose what to share in the browser dialog.');
  const low = el<HTMLSelectElement>('quality').value === 'low';
  // Invoke synchronously inside the click: the source picker requires transient activation.
  const display = navigator.mediaDevices.getDisplayMedia({
    video: {
      width: {ideal: low ? 1280 : 1920},
      height: {ideal: low ? 720 : 1080},
      frameRate: {ideal: 30, max: 30},
    },
    audio: el<HTMLInputElement>('audio').checked,
  });
  // Attach a rejection handler immediately while the profile lock is acquired.
  void display.catch(() => {});
  // Both APIs are invoked in the Record click while user activation is available.
  void floating.open().catch(() => {});
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
    if (!locked) {
      void display.then((s) => s.getTracks().forEach((t) => t.stop())).catch(() => {});
      throw new Error('Another Hot Take recorder is active. Stop that recording first.');
    }
    capture = await acquire(display, {
      low,
      mic: el<HTMLInputElement>('mic').checked,
      camera: el<HTMLInputElement>('camera').checked,
      audio: el<HTMLInputElement>('audio').checked,
    });
    void navigator.storage.persist().catch(() => {});
    const estimate = await navigator.storage.estimate();
    if (estimate.quota && estimate.quota - (estimate.usage || 0) < 100 * 1024 * 1024)
      throw new Error(
        'Less than 100 MB of browser storage is available. Download and delete old takes first.',
      );
    capture.stream.addEventListener('sourceended', end, {once: true});
    capture.stream
      .getAudioTracks()
      .forEach((track) =>
        track.addEventListener('ended', () =>
          status('An audio input ended. Video recording continues.'),
        ),
      );
    monitor.srcObject = capture.stream;
    void monitor.play().catch(() => {});
    await beginTake();
  } catch (error) {
    countdownSound.close();
    floating.close();
    void display.then((s) => s.getTracks().forEach((t) => t.stop())).catch(() => {});
    capture?.dispose();
    capture = undefined;
    release?.();
    release = undefined;
    busy = false;
    recorder = undefined;
    controls(false);
    status(error instanceof Error ? error.message : 'Could not start recording.');
    el('state').textContent = 'Ready';
  }
});
pause.onclick = () => {
  if (!recorder || stopping) return;
  if (recorder.state === 'recording') {
    recorder.pause();
    clock.pause();
    iconLabel(pause, 'play', 'Resume');
    el('state').textContent = 'Paused';
  } else if (recorder.state === 'paused') {
    recorder.resume();
    clock.resume();
    iconLabel(pause, 'pause', 'Pause');
    el('state').textContent = 'Recording';
  }
};
stop.onclick = end;
setInterval(() => {
  el('timer').textContent = duration(clock.elapsed);
  if (recorder?.state === 'recording') {
    if (clock.elapsed >= 30 * 60 * 1000) end();
    else if (clock.elapsed >= 25 * 60 * 1000 && !warningShown) {
      warningShown = true;
      status('Five minutes remain before this take stops automatically.');
    }
  }
}, 250);
window.addEventListener('beforeunload', (event) => {
  if (busy) {
    event.preventDefault();
  }
});
function button(text: string, action: () => void | Promise<void>) {
  const b = document.createElement('button');
  const names: Record<string, IconName> = {
    Edit: 'scissors',
    Preview: 'play',
    Download: 'download',
    Rename: 'pencil',
    Delete: 'trash',
    Recover: 'refresh',
  };
  if (names[text]) {
    b.innerHTML = iconSvg(names[text]);
    b.setAttribute('aria-label', text);
    b.title = text;
    b.classList.add('icon-button');
  } else b.textContent = text;
  b.onclick = () => {
    void Promise.resolve(action()).catch((error) =>
      status(error instanceof Error ? error.message : 'Action failed.'),
    );
  };
  return b;
}
const thumbnails = new ThumbnailQueue();
window.addEventListener('pagehide', () => thumbnails.reset());
async function refresh() {
  const rows = await storage.list();
  thumbnails.reset();
  el('count').textContent = String(rows.length);
  const container = el('recordings');
  container.replaceChildren();
  if (!rows.length) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'No recordings yet';
    container.append(empty);
  }
  for (const row of rows) {
    const card = document.createElement('article');
    card.className = 'take';
    const detail = document.createElement(row.status === 'recording' ? 'div' : 'button');
    detail.className = 'take-open';
    const play = document.createElement('span');
    play.className = 'take-play';
    play.innerHTML = iconSvg(row.status === 'recording' ? 'clock' : 'play');
    const content = document.createElement('span');
    content.className = 'take-description';
    const title = document.createElement('span');
    title.className = 'take-title';
    title.textContent = row.title;
    const meta = document.createElement('span');
    meta.className = 'take-meta';
    meta.textContent = `${new Date(row.created).toLocaleDateString()} · ${duration(row.duration)}${row.status === 'ready' ? '' : row.status === 'recording' ? ' · Active / interrupted' : ' · Recovered'}`;
    detail.title = `${new Date(row.created).toLocaleString()} · ${bytes(row.size)}`;
    content.append(title, meta);
    detail.append(play, content);
    if (row.status !== 'recording') {
      detail.setAttribute('aria-label', `Play ${row.title}`);
      detail.onclick = () => {
        void previewRecording(row).catch(() => status('Could not open recording.'));
      };
    }
    const actions = document.createElement('div');
    actions.className = 'take-actions';
    if (row.status === 'recording') {
      actions.append(
        button('Recover', async () => {
          await navigator.locks.request('relaytake-recorder', {ifAvailable: true}, async (lock) => {
            if (!lock) {
              status('A recorder is still active. Stop it before recovery.');
              return;
            }
            await storage.finalize(row.id, row.duration, true);
            await refresh();
            status(
              'Committed bytes recovered. The container may be incomplete; preview or download to check.',
            );
          });
        }),
      );
    }

    if (row.status === 'ready')
      actions.append(
        button('Edit', () => {
          location.href = `./editor.html?id=${encodeURIComponent(row.id)}`;
        }),
      );
    actions.append(
      button('Download', async () => {
        const url = URL.createObjectURL(await storage.readBlob(row));
        const a = document.createElement('a');
        a.href = url;
        a.download = filename(row.title, row.mime);
        a.click();
        setTimeout(() => URL.revokeObjectURL(url), 60000);
      }),
    );
    if (row.status !== 'recording') {
      actions.append(
        button('Rename', async () => {
          const title = prompt('Recording title', row.title);
          if (title?.trim()) {
            await storage.save({...row, title: title.trim().slice(0, 120)});
            await refresh();
          }
        }),
        button('Delete', async () => {
          if (
            confirm(
              `Delete “${row.title}” from this browser? This cannot be undone. Download a copy first if you need it.`,
            )
          ) {
            await storage.remove(row.id);
            await refresh();
          }
        }),
      );
    }
    card.append(detail, actions);
    container.append(card);
    if (row.status !== 'recording') thumbnails.add(row, play);
  }
}
el('refresh').onclick = () => {
  void refresh().catch(() => status('Could not read the local library.'));
};
el('close-preview').onclick = () => el<HTMLDialogElement>('preview').close();
el<HTMLDialogElement>('preview').addEventListener('close', () => {
  const v = el<HTMLVideoElement>('playback');
  v.pause();
  v.removeAttribute('src');
  v.load();
  if (objectURL) URL.revokeObjectURL(objectURL);
  objectURL = undefined;
});
controls(false);
void refresh()
  .then(async () => {
    const previewId = params.get('preview');
    if (previewId) {
      const row = (await storage.list()).find((r) => r.id === previewId);
      if (row && row.status !== 'recording') await previewRecording(row);
      else status('This take is unavailable or needs recovery in your library.');
    }
  })
  .catch(() => status('Local storage is unavailable. Recording requires IndexedDB.'));
