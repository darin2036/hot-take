import {describe, it, expect} from 'vitest';
import {visibleText, clamp, type TextOverlay} from '../src/text-overlay';
const text: TextOverlay = {
  id: 'a',
  text: 'Hello',
  start: 2,
  end: 3,
  x: 0.5,
  y: 0.5,
  size: 'medium',
  color: '#ffffff',
};
describe('text overlay timing', () => {
  it('uses source timestamps and excludes the end boundary', () => {
    expect(visibleText([text], 1.99)).toEqual([]);
    expect(visibleText([text], 2)).toEqual([text]);
    expect(visibleText([text], 2.9)).toEqual([text]);
    expect(visibleText([text], 3)).toEqual([]);
  });
  it('omits blank text and keeps positions on the video', () => {
    expect(visibleText([{...text, text: '   '}], 2.5)).toEqual([]);
    expect(clamp(-1)).toBe(0);
    expect(clamp(2)).toBe(1);
    expect(clamp(0.4)).toBe(0.4);
  });
});
