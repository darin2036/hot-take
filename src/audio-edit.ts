import type {Segment} from './edit-model';
export interface AudioClip {
  kind: 'file' | 'voice';
  name: string;
  buffer: AudioBuffer;
  start: number;
  volume: number;
}
export interface AudioEdit {
  original: number;
  clips: AudioClip[];
}
export const emptyAudio = (): AudioEdit => ({original: 1, clips: []});
export const copyAudio = (edit: AudioEdit): AudioEdit => ({
  original: edit.original,
  clips: edit.clips.map((c) => ({...c})),
});
/** Added audio runs on the edited timeline, continuously across source cuts. */
export function editedTime(segments: Segment[], sourceTime: number) {
  let elapsed = 0;
  for (const s of segments) {
    if (sourceTime < s.start) return elapsed;
    if (sourceTime < s.end) return elapsed + sourceTime - s.start;
    elapsed += s.end - s.start;
  }
  return elapsed;
}
export function playClips(
  context: AudioContext,
  destination: AudioNode,
  edit: AudioEdit,
  time: number,
  duration = Infinity,
  rate = 1,
) {
  const nodes: AudioBufferSourceNode[] = [];
  for (const clip of edit.clips) {
    const offset = Math.max(0, time - clip.start),
      delay = Math.max(0, clip.start - time),
      remaining = Math.min(clip.buffer.duration - offset, duration - delay);
    if (remaining <= 0 || clip.volume === 0) continue;
    const source = context.createBufferSource(),
      gain = context.createGain();
    source.buffer = clip.buffer;
    source.playbackRate.value = rate;
    gain.gain.value = clip.volume;
    source.connect(gain).connect(destination);
    source.onended = () => {
      source.disconnect();
      gain.disconnect();
    };
    source.start(context.currentTime + delay / rate, offset, remaining);
    nodes.push(source);
  }
  return () => {
    nodes.forEach((n) => {
      try {
        n.stop();
      } catch {}
      n.disconnect();
    });
  };
}
