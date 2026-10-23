import {bindInputs} from './preferences';
import {iconSvg, iconLabel} from './icons';
import './style.css';
import './popup.css';
import {duration} from './core';
import {requestControl, type Snapshot} from './control';
import {isExtension, openSurface} from './navigation';

document.body.classList.add('toolbar');
document.querySelector('#popup')!.innerHTML =
  `<header><a class="brand" href="#" id="brand"><img class="brand-icon" src="./favicon.svg" alt="">Hot Take</a><details class="settings-menu"><summary aria-label="Recording settings" title="Settings">${iconSvg('menu')}</summary><div class="settings-panel" id="settings-panel"></div></details></header>
<main><section id="setup" aria-label="Recording setup"><button id="new" class="primary" aria-label="New recording">${iconSvg('circle')} Start recording</button></section>
<section id="live" hidden aria-label="Recording controls"><div class="section-heading"><span id="live-state" class="pill">Recording</span><button id="show-recorder" class="icon-button" aria-label="Open recorder" title="Open recorder">${iconSvg('external')}</button></div><h2 id="live-title">Your take</h2><div id="elapsed" aria-label="Recording duration">00:00</div><div class="actions"><button id="pause">${iconSvg('pause')} Pause</button><button id="restart" class="icon-button" aria-label="Restart recording" title="Restart and discard current take">${iconSvg('refresh')}</button><button id="stop" class="danger" aria-label="Stop & save">${iconSvg('square')} Stop</button></div></section>
<p id="notice" role="status" aria-live="polite"></p>
<button id="library" class="library-button">${iconSvg('library')} Library</button></main>`;
document.querySelector('#settings-panel')!.innerHTML =
  `<fieldset id="choices"><legend class="sr-only">Recording options</legend><label class="choice"><span>${iconSvg('video')} Camera</span><input id="camera" type="checkbox" aria-label="Camera"></label><label class="choice"><span>${iconSvg('mic')} Microphone</span><input id="mic" type="checkbox" aria-label="Microphone"></label><label class="choice"><span>${iconSvg('volume')} Source audio</span><input id="audio" type="checkbox" aria-label="Source audio"></label></fieldset>`;
const el = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
let current: Snapshot | null = null,
  polling = false,
  commandPending = false,
  revision = 0;
function notice(text: string) {
  el('notice').textContent = text;
}
function render(snapshot: Snapshot | null) {
  current = snapshot;
  el('live').hidden = !snapshot;
  el('setup').hidden = !!snapshot;
  el<HTMLButtonElement>('new').disabled = false;
  el<HTMLFieldSetElement>('choices').disabled = !!snapshot;
  if (!snapshot) return;
  el('live-title').textContent = snapshot.title || 'Untitled take';
  el('elapsed').textContent = duration(snapshot.elapsed);
  el('live-state').textContent = {
    starting: 'Choose a source',
    countdown: String(snapshot.countdown || 'Get ready'),
    recording: 'Recording',
    paused: 'Paused',
    saving: 'Saving your take…',
  }[snapshot.state];
  iconLabel(
    el('pause'),
    snapshot.state === 'paused' ? 'play' : 'pause',
    snapshot.state === 'paused' ? 'Resume' : 'Pause',
  );
  const enabled = ['recording', 'paused'].includes(snapshot.state) && !commandPending;
  el<HTMLButtonElement>('restart').disabled = !enabled;
  el<HTMLButtonElement>('pause').disabled = !enabled;
  el<HTMLButtonElement>('stop').disabled =
    (!enabled && snapshot.state !== 'countdown') || commandPending;
  el('live').classList.toggle('paused', snapshot.state === 'paused');
}
async function launch(view: 'recorder' | 'library', params = new URLSearchParams()) {
  try {
    await openSurface(view, params);
    if (isExtension) window.close();
  } catch {
    notice('Could not open this window. Try reopening the extension.');
    el<HTMLButtonElement>('new').disabled = false;
  }
}
async function poll() {
  if (polling || commandPending) return;
  polling = true;
  const startedAtRevision = revision;
  try {
    const result = await requestControl('status');
    if (!commandPending && startedAtRevision === revision) {
      render(result);
      notice('');
    }
  } catch {
    notice('Could not reach the recorder. Reopen the extension to try again.');
  } finally {
    polling = false;
  }
}
async function command(action: 'pause' | 'resume' | 'stop' | 'restart') {
  if (!current || commandPending) return;
  commandPending = true;
  revision++;
  const owner = current.owner;
  render(current);
  try {
    const response = await requestControl(action, owner);
    if (response) {
      render(response);
      notice(action === 'stop' ? 'Saving your take in the local library.' : '');
    } else {
      notice('Recorder did not respond. Open its window to check; no recording was deleted.');
    }
  } finally {
    commandPending = false;
    if (current) render(current);
  }
}
bindInputs();
el<HTMLButtonElement>('new').disabled = true;
el('new').onclick = () => {
  el<HTMLButtonElement>('new').disabled = true;
  const params = new URLSearchParams();
  for (const name of ['mic', 'camera', 'audio'])
    params.set(name, el<HTMLInputElement>(name).checked ? '1' : '0');
  void launch('recorder', params);
};
el('pause').onclick = () => {
  void command(current?.state === 'paused' ? 'resume' : 'pause');
};
el('stop').onclick = () => {
  void command('stop');
};
el('restart').onclick = () => {
  void command('restart');
};
el('show-recorder').onclick = () => {
  void launch('recorder');
};
el('library').onclick = () => {
  void launch('library');
};
el('brand').onclick = (event) => {
  event.preventDefault();
  void launch('library');
};
void poll();
setInterval(() => {
  void poll();
}, 1800);

import {bindSettingsMenu} from './settings-menu';
bindSettingsMenu();
