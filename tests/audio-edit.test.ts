import {describe, it, expect} from 'vitest';
import {editedTime, copyAudio} from '../src/audio-edit';
describe('edited audio timeline', () => {
  it('keeps music continuous across removed source ranges', () => {
    const segments = [
      {start: 1, end: 3},
      {start: 5, end: 7},
    ];
    expect(editedTime(segments, 0)).toBe(0);
    expect(editedTime(segments, 2)).toBe(1);
    expect(editedTime(segments, 4)).toBe(2);
    expect(editedTime(segments, 6)).toBe(3);
    expect(editedTime(segments, 9)).toBe(4);
  });
  it('isolates undo settings without copying decoded audio', () => {
    const buffer = {} as AudioBuffer;
    const original = {
      original: 0.5,
      clips: [{kind: 'file' as const, name: 'Music', buffer, start: 1, volume: 0.5}],
    };
    const copy = copyAudio(original);
    copy.clips[0].volume = 0;
    expect(original.clips[0].volume).toBe(0.5);
    expect(copy.clips[0].buffer).toBe(buffer);
  });
});
