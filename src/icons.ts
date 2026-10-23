import scissors from 'lucide-static/icons/scissors.svg?raw';
import undo from 'lucide-static/icons/undo-2.svg?raw';
import trim from 'lucide-static/icons/crop.svg?raw';
import markIn from 'lucide-static/icons/arrow-left-to-line.svg?raw';
import markOut from 'lucide-static/icons/arrow-right-to-line.svg?raw';
import menu from 'lucide-static/icons/menu.svg?raw';
import monitor from 'lucide-static/icons/monitor.svg?raw';
import video from 'lucide-static/icons/video.svg?raw';
import mic from 'lucide-static/icons/mic.svg?raw';
import volume from 'lucide-static/icons/volume-2.svg?raw';
import circle from 'lucide-static/icons/circle.svg?raw';
import pause from 'lucide-static/icons/pause.svg?raw';
import play from 'lucide-static/icons/play.svg?raw';
import square from 'lucide-static/icons/square.svg?raw';
import external from 'lucide-static/icons/external-link.svg?raw';
import library from 'lucide-static/icons/library.svg?raw';
import clock from 'lucide-static/icons/clock.svg?raw';
import download from 'lucide-static/icons/download.svg?raw';
import pencil from 'lucide-static/icons/pencil.svg?raw';
import trash from 'lucide-static/icons/trash-2.svg?raw';
import refresh from 'lucide-static/icons/refresh-cw.svg?raw';
import shield from 'lucide-static/icons/shield-check.svg?raw';
import check from 'lucide-static/icons/check.svg?raw';
import close from 'lucide-static/icons/x.svg?raw';

const icons = {
  scissors,
  undo,
  trim,
  markIn,
  markOut,
  menu,
  monitor,
  video,
  mic,
  volume,
  circle,
  pause,
  play,
  square,
  external,
  library,
  clock,
  download,
  pencil,
  trash,
  refresh,
  shield,
  check,
  close,
};
export type IconName = keyof typeof icons;
/** Only bundled, trusted SVG sources. Decorative icons leave labels to their controls. */
export function iconSvg(name: IconName): string {
  return icons[name]
    .replace(/<!--.*?-->/gs, '')
    .replace(/\sxmlns="[^"]*"/, '')
    .replace(/class="[^"]*"/, 'class="icon"')
    .replace('<svg', '<svg aria-hidden="true" focusable="false"');
}
export function iconLabel(element: HTMLElement, name: IconName, label: string) {
  element.innerHTML = iconSvg(name);
  const text = document.createElement('span');
  text.textContent = label;
  element.append(text);
}
