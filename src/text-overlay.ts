export interface TextOverlay {
  id: string;
  text: string;
  start: number;
  end: number;
  x: number;
  y: number;
  size: 'small' | 'medium' | 'large';
  color: string;
}
export const clamp = (value: number) => Math.max(0, Math.min(1, value));
export function visibleText(overlays: TextOverlay[], time: number) {
  return overlays.filter((t) => t.text.trim() && time >= t.start && time < t.end);
}
/** Positions and font sizes scale with the source video, not the editor viewport. */
export function textLayout(
  ctx: CanvasRenderingContext2D,
  t: TextOverlay,
  width: number,
  height: number,
) {
  let fontSize = height * {small: 0.035, medium: 0.055, large: 0.085}[t.size];
  const padding = height * 0.012;
  ctx.font = `600 ${fontSize}px Arial, sans-serif`;
  const measured = ctx.measureText(t.text).width;
  if (measured > width * 0.9 - padding * 2) {
    fontSize *= (width * 0.9 - padding * 2) / measured;
    ctx.font = `600 ${fontSize}px Arial, sans-serif`;
  }
  const w = ctx.measureText(t.text).width + padding * 2,
    h = fontSize * 1.3 + padding * 2;
  return {
    x: clamp(t.x) * (width - w),
    y: clamp(t.y) * (height - h),
    width: w,
    height: h,
    padding,
    fontSize,
  };
}
export function drawText(
  ctx: CanvasRenderingContext2D,
  overlays: TextOverlay[],
  time: number,
  width: number,
  height: number,
) {
  ctx.save();
  for (const t of visibleText(overlays, time)) {
    const box = textLayout(ctx, t, width, height);
    ctx.fillStyle = 'rgba(0,0,0,.65)';
    ctx.fillRect(box.x, box.y, box.width, box.height);
    ctx.fillStyle = t.color;
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'left';
    ctx.fillText(t.text, box.x + box.padding, box.y + box.height / 2);
  }
  ctx.restore();
}
