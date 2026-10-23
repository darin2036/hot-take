export interface Segment {
  start: number;
  end: number;
}
export function length(segments: Segment[]) {
  return segments.reduce((sum, s) => sum + s.end - s.start, 0);
}
export function changeRange(
  segments: Segment[],
  start: number,
  end: number,
  keep = false,
): Segment[] {
  if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end <= start)
    throw new Error('Select a valid time range.');
  const next = segments
    .flatMap((s) =>
      keep
        ? [{start: Math.max(s.start, start), end: Math.min(s.end, end)}]
        : [
            {start: s.start, end: Math.min(s.end, start)},
            {start: Math.max(s.start, end), end: s.end},
          ],
    )
    .filter((s) => s.end - s.start >= 0.05);
  if (length(next) < 0.1) throw new Error('Keep at least a moment of the recording.');
  return next;
}
export function timeLabel(seconds: number) {
  const m = Math.floor(seconds / 60);
  return `${String(m).padStart(2, '0')}:${(seconds % 60).toFixed(1).padStart(4, '0')}`;
}
