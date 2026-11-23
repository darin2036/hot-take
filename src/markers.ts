/** Chapter markers placed while recording. Times are seconds of active (unpaused) recording. */
export interface Marker {
  time: number;
  title: string;
}
export const MAX_MARKERS = 200;
const MIN_GAP = 0.5;
export function addMarker(markers: Marker[], elapsedMs: number, title?: string): Marker[] {
  const time = Math.max(0, Math.round(elapsedMs / 100) / 10);
  if (markers.length >= MAX_MARKERS) return markers;
  const last = markers[markers.length - 1];
  if (last && time - last.time < MIN_GAP) return markers;
  const name = title?.trim().slice(0, 80) || `Marker ${markers.length + 1}`;
  return [...markers, {time, title: name}];
}
/** Never trust stored metadata: drop anything malformed and keep chronological order. */
export function cleanMarkers(value: unknown): Marker[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter(
      (m): m is Marker =>
        !!m &&
        typeof m.time === 'number' &&
        Number.isFinite(m.time) &&
        m.time >= 0 &&
        typeof m.title === 'string',
    )
    .map((m) => ({time: m.time, title: m.title.slice(0, 80)}))
    .sort((a, b) => a.time - b.time)
    .slice(0, MAX_MARKERS);
}
export function timestamp(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600),
    m = Math.floor((s % 3600) / 60),
    sec = s % 60;
  const two = (n: number) => String(n).padStart(2, '0');
  return h ? `${h}:${two(m)}:${two(sec)}` : `${m}:${two(sec)}`;
}
/** "0:12 Title" lines, one per marker, ready to paste into a description or a message. */
export function timestampList(markers: Marker[]): string {
  return markers.map((m) => `${timestamp(m.time)} ${m.title}`).join('\n');
}
function vttTime(seconds: number): string {
  const ms = Math.round(seconds * 1000);
  const two = (n: number, w = 2) => String(n).padStart(w, '0');
  return `${two(Math.floor(ms / 3600000))}:${two(Math.floor(ms / 60000) % 60)}:${two(Math.floor(ms / 1000) % 60)}.${two(ms % 1000, 3)}`;
}
/** A WebVTT chapters file: each marker lasts until the next one (or the end of the take). */
export function chaptersVtt(markers: Marker[], durationSeconds: number): string {
  const lines = ['WEBVTT', ''];
  markers.forEach((m, i) => {
    const end = Math.max(markers[i + 1]?.time ?? durationSeconds, m.time + 1);
    lines.push(`${vttTime(m.time)} --> ${vttTime(end)}`, m.title.replace(/-->/g, '→'), '');
  });
  return lines.join('\n');
}
export const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 2] as const;
export function speedLabel(speed: number): string {
  return `${speed}×`;
}
