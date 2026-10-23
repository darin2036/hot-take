export function filename(title: string, mime: string): string {
  return (
    (title
      .replace(/[\\/:*?"<>|\x00-\x1f]/g, '-')
      .trim()
      .slice(0, 120) || 'Recording') + (mime.includes('mp4') ? '.mp4' : '.webm')
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
