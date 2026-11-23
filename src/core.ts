export function safeTitle(title: string): string {
  return (
    title
      .replace(/[\\/:*?"<>|\x00-\x1f]/g, '-')
      .trim()
      .slice(0, 120) || 'Recording'
  );
}
export function filename(title: string, mime: string): string {
  return (
    safeTitle(title) +
    (mime.includes('mp4') ? '.mp4' : mime.includes('quicktime') ? '.mov' : '.webm')
  );
}
export function duration(ms: number): string {
  const s = Math.floor(ms / 1000);
  return `${Math.floor(s / 60)
    .toString()
    .padStart(2, '0')}:${(s % 60).toString().padStart(2, '0')}`;
}
export function bytes(n: number): string {
  const size = Number.isFinite(n) ? Math.max(0, n) : 0;
  const units = ['bytes', 'KB', 'MB', 'GB', 'TB'];
  const index = size < 1000 ? 0 : Math.min(4, Math.floor(Math.log10(size) / 3));
  return `${new Intl.NumberFormat(undefined, {maximumFractionDigits: index === 0 ? 0 : 1}).format(size / 1000 ** index)} ${units[index]}`;
}
export class ActiveClock {
  private accumulated = 0;
  private started: number | null = null;
  constructor(private now = () => performance.now()) {}
  resume() {
    if (this.started === null) this.started = this.now();
  }
  pause() {
    if (this.started !== null) {
      this.accumulated += this.now() - this.started;
      this.started = null;
    }
  }
  get elapsed() {
    return this.accumulated + (this.started === null ? 0 : this.now() - this.started);
  }
}
/** The container to record for an imported file, or '' when it is not a supported video. */
export function importMime(name: string, type: string): string {
  const t = type.toLowerCase();
  if (t === 'video/mp4' || t === 'video/webm' || t === 'video/quicktime') return t;
  const ext = name.toLowerCase().match(/\.([a-z0-9]+)$/)?.[1];
  return ext === 'mp4' || ext === 'm4v'
    ? 'video/mp4'
    : ext === 'mov'
      ? 'video/quicktime'
      : ext === 'webm'
        ? 'video/webm'
        : '';
}
