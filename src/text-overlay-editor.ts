import {clamp, drawText, textLayout, visibleText, type TextOverlay} from './text-overlay';
import {iconSvg} from './icons';
export function setupTextEditor(
  video: HTMLVideoElement,
  read: () => TextOverlay[],
  commit: () => void,
  changed: () => void,
  duration: () => number,
  locked: () => boolean,
) {
  const stage = document.createElement('div');
  stage.className = 'edit-stage';
  video.before(stage);
  stage.append(video);
  video.setAttribute('controlsList', 'nofullscreen');
  video.disablePictureInPicture = true;
  const layer = document.createElement('div');
  layer.className = 'text-layer';
  stage.append(layer);
  const canvas = document.createElement('canvas');
  layer.append(canvas);
  const ctx = canvas.getContext('2d')!;
  const panel = document.createElement('div');
  panel.className = 'text-tools';
  panel.innerHTML = `<button id="add-text">Add text</button><div id="text-options" hidden><select id="text-select" aria-label="Text overlay"></select><input id="overlay-text" aria-label="Overlay text" maxlength="180" placeholder="Your text"><label>From <input id="text-from" aria-label="Text start in seconds" type="number" min="0" step="0.1"></label><label>To <input id="text-to" aria-label="Text end in seconds" type="number" min="0" step="0.1"></label><select id="text-size" aria-label="Text size"><option value="small">Small</option><option value="medium">Medium</option><option value="large">Large</option></select><input id="text-color" aria-label="Text color" type="color" value="#ffffff"><button id="delete-text" class="icon-button" aria-label="Delete text" title="Delete text">${iconSvg('trash')}</button></div>`;
  document.querySelector('#edit-tools')!.prepend(panel);
  const el = <T extends HTMLElement>(id: string) => panel.querySelector<T>('#' + id)!;
  let selected = '',
    drag:
      | {
          id: string;
          px: number;
          py: number;
          x: number;
          y: number;
          dx: number;
          dy: number;
          saved: boolean;
        }
      | undefined;
  const handles = new Map<string, HTMLButtonElement>();
  const targets = new WeakMap<HTMLButtonElement, TextOverlay>();
  const current = () => read().find((t) => t.id === selected);
  function render() {
    if (!current()) selected = read()[0]?.id || '';
    const t = current();
    el('text-options').hidden = !t;
    panel.querySelectorAll('input').forEach((input) => input.setCustomValidity(''));
    const select = el<HTMLSelectElement>('text-select');
    select.replaceChildren();
    read().forEach((item, index) => {
      const option = document.createElement('option');
      option.value = item.id;
      option.textContent = item.text || `Text ${index + 1}`;
      select.append(option);
    });
    select.value = selected;
    select.hidden = read().length < 2;
    if (t) {
      el<HTMLInputElement>('overlay-text').value = t.text;
      el<HTMLInputElement>('text-from').value = String(t.start);
      el<HTMLInputElement>('text-to').value = String(t.end);
      el<HTMLSelectElement>('text-size').value = t.size;
      el<HTMLInputElement>('text-color').value = t.color;
    }
    paint();
  }
  function paint() {
    if (!video.videoWidth) return;
    const w = video.videoWidth,
      h = video.videoHeight,
      scale = Math.min(video.clientWidth / w, video.clientHeight / h);
    Object.assign(layer.style, {
      width: `${w * scale}px`,
      height: `${h * scale}px`,
      left: `${(video.clientWidth - w * scale) / 2}px`,
      top: `${(video.clientHeight - h * scale) / 2}px`,
    });
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
    ctx.clearRect(0, 0, w, h);
    drawText(ctx, read(), video.currentTime, w, h);
    const visible = visibleText(read(), video.currentTime);
    for (const [id, button] of handles)
      if (!visible.some((t) => t.id === id && t === targets.get(button))) {
        button.remove();
        handles.delete(id);
      }
    for (const t of visible) {
      let button = handles.get(t.id);
      if (!button) {
        button = document.createElement('button');
        button.className = 'text-handle';
        button.type = 'button';
        layer.append(button);
        handles.set(t.id, button);
        targets.set(button, t);
        button.onpointerdown = (event) => {
          if (locked()) return;
          event.preventDefault();
          video.pause();
          selected = t.id;
          render();
          button!.focus();
          const box = textLayout(ctx, t, w, h);
          drag = {
            id: t.id,
            px: event.clientX,
            py: event.clientY,
            x: t.x,
            y: t.y,
            dx: Math.max(1, (w - box.width) * scale),
            dy: Math.max(1, (h - box.height) * scale),
            saved: false,
          };
          button!.setPointerCapture(event.pointerId);
        };
        button.onpointermove = (event) => {
          if (!drag || drag.id !== t.id || locked()) return;
          if (!drag.saved) {
            if (Math.hypot(event.clientX - drag.px, event.clientY - drag.py) < 2) return;
            commit();
            drag.saved = true;
          }
          t.x = clamp(drag.x + (event.clientX - drag.px) / drag.dx);
          t.y = clamp(drag.y + (event.clientY - drag.py) / drag.dy);
          paint();
        };
        const finish = () => {
          const saved = drag?.saved;
          drag = undefined;
          if (saved) changed();
        };
        button.onpointerup = finish;
        button.onpointercancel = finish;
        button.onlostpointercapture = finish;
        button.onkeydown = (event) => {
          if (locked() || !['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key))
            return;
          event.preventDefault();
          commit();
          selected = t.id;
          const step = event.shiftKey ? 0.05 : 0.01;
          t.x = clamp(
            t.x + (event.key === 'ArrowRight' ? step : event.key === 'ArrowLeft' ? -step : 0),
          );
          t.y = clamp(
            t.y + (event.key === 'ArrowDown' ? step : event.key === 'ArrowUp' ? -step : 0),
          );
          changed();
          render();
        };
      }
      const box = textLayout(ctx, t, w, h);
      Object.assign(button.style, {
        left: `${(box.x / w) * 100}%`,
        top: `${(box.y / h) * 100}%`,
        width: `${(box.width / w) * 100}%`,
        height: `${(box.height / h) * 100}%`,
      });
      button.classList.toggle('selected', t.id === selected);
      button.disabled = locked();
      button.setAttribute('aria-label', `Move text: ${t.text}`);
    }
  }
  el('add-text').onclick = () => {
    if (locked() || duration() <= 0) return;
    video.pause();
    commit();
    const start = Math.min(video.currentTime, Math.max(0, duration() - 0.1));
    const t: TextOverlay = {
      id: crypto.randomUUID(),
      text: 'Your text',
      start: Number(start.toFixed(2)),
      end: duration(),
      x: 0.5,
      y: 0.8,
      size: 'medium',
      color: '#ffffff',
    };
    read().push(t);
    selected = t.id;
    changed();
    render();
    el<HTMLInputElement>('overlay-text').focus();
    el<HTMLInputElement>('overlay-text').select();
  };
  el('text-select').onchange = () => {
    selected = el<HTMLSelectElement>('text-select').value;
    const t = current();
    if (t) {
      video.pause();
      video.currentTime = t.start;
    }
    render();
  };
  el('delete-text').onclick = () => {
    const index = read().findIndex((t) => t.id === selected);
    if (index < 0 || locked()) return;
    commit();
    read().splice(index, 1);
    changed();
    render();
  };
  let typing = false;
  el('overlay-text').onfocus = () => {
    typing = false;
  };
  el('overlay-text').onblur = () => {
    typing = false;
  };
  el('overlay-text').oninput = () => {
    const t = current();
    if (!t || locked()) return;
    if (!typing) {
      commit();
      typing = true;
    }
    t.text = el<HTMLInputElement>('overlay-text').value;
    changed();
  };
  for (const id of ['text-from', 'text-to', 'text-size', 'text-color'])
    el(id).onchange = () => {
      const t = current();
      if (!t || locked()) return;
      const start = Number(el<HTMLInputElement>('text-from').value),
        end = Number(el<HTMLInputElement>('text-to').value);
      const input = el<HTMLInputElement>(id);
      input.setCustomValidity('');
      if (
        !Number.isFinite(start) ||
        !Number.isFinite(end) ||
        start < 0 ||
        end > duration() ||
        end - start < 0.05
      ) {
        input.setCustomValidity('Choose a time range inside the recording.');
        input.reportValidity();
        return;
      }
      commit();
      Object.assign(t, {
        text: el<HTMLInputElement>('overlay-text').value,
        start,
        end,
        size: el<HTMLSelectElement>('text-size').value,
        color: el<HTMLInputElement>('text-color').value,
      });
      changed();
      render();
    };
  const observer = new ResizeObserver(paint);
  observer.observe(video);
  // Frame-synchronized preview uses exactly the same source clock and drawing as export.
  let frame = 0;
  const loop = () => {
    paint();
    frame = requestAnimationFrame(loop);
  };
  loop();
  window.addEventListener(
    'pagehide',
    () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
    },
    {once: true},
  );
  return {render};
}
