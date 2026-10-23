import {iconSvg, iconLabel} from './icons';
import {duration} from './core';
import type {Snapshot} from './control';
type Action = 'pause' | 'restart' | 'stop';
type PiPWindow = Window & {
  documentPictureInPicture?: {
    requestWindow(options: {width: number; height: number}): Promise<Window>;
  };
};
/** The recorder remains the media owner; closing these controls never stops capture. */
export class FloatingControls {
  private window?: Window;
  private interval?: ReturnType<typeof setInterval>;
  private opening?: Promise<void>;
  private generation = 0;
  constructor(
    private snapshot: () => Snapshot,
    private action: (action: Action) => void,
  ) {}
  open(): Promise<void> {
    if (this.window && !this.window.closed) {
      this.window.focus();
      return Promise.resolve();
    }
    if (this.opening) return this.opening;
    const api = (window as PiPWindow).documentPictureInPicture;
    if (!api) return Promise.reject(new Error('Picture-in-Picture unavailable'));
    const generation = this.generation;
    this.opening = api
      .requestWindow({width: 340, height: 160})
      .then((pip) => {
        if (generation !== this.generation) {
          pip.close();
          return;
        }
        this.window = pip;
        pip.document.title = 'Hot Take';
        for (const sheet of document.querySelectorAll('style,link[rel="stylesheet"]'))
          pip.document.head.append(sheet.cloneNode(true));
        pip.document.body.className = 'floating-controls';
        pip.document.body.innerHTML = `<div class="floating-state" role="status"></div><div class="floating-time">00:00</div><div class="actions"><button data-action="pause">${iconSvg('pause')} Pause</button><button data-action="restart" title="Restart and discard current take" aria-label="Restart recording">${iconSvg('refresh')}</button><button class="danger" data-action="stop">${iconSvg('square')} Stop</button></div>`;
        pip.document
          .querySelectorAll<HTMLButtonElement>('[data-action]')
          .forEach(
            (button) => (button.onclick = () => this.action(button.dataset.action as Action)),
          );
        const render = () => {
          const s = this.snapshot(),
            active = s.state === 'recording' || s.state === 'paused';
          pip.document.querySelector('.floating-state')!.textContent = {
            starting: 'Choose a source',
            countdown: 'Get ready',
            recording: 'Recording',
            paused: 'Paused',
            saving: 'Saving…',
          }[s.state];
          pip.document.querySelector('.floating-time')!.textContent =
            s.state === 'countdown' ? String(s.countdown) : duration(s.elapsed);
          for (const button of pip.document.querySelectorAll<HTMLButtonElement>('button'))
            button.disabled =
              button.dataset.action === 'stop' ? !active && s.state !== 'countdown' : !active;
          iconLabel(
            pip.document.querySelector('[data-action="pause"]')!,
            s.state === 'paused' ? 'play' : 'pause',
            s.state === 'paused' ? 'Resume' : 'Pause',
          );
        };
        render();
        this.interval = setInterval(render, 150);
        pip.addEventListener(
          'pagehide',
          () => {
            clearInterval(this.interval);
            this.window = undefined;
          },
          {once: true},
        );
      })
      .finally(() => {
        this.opening = undefined;
      });
    return this.opening;
  }
  close() {
    this.generation++;
    this.window?.close();
    clearInterval(this.interval);
  }
}
