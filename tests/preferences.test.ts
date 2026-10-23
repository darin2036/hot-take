import {it, expect} from 'vitest';
import {inputNames, readInput, saveInput} from '../src/preferences';
it('starts every input on, but preserves explicitly disabled inputs', () => {
  const values = new Map<string, string>();
  const store = {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => {
      values.set(key, value);
    },
  };
  for (const name of inputNames) expect(readInput(name, store)).toBe(true);
  saveInput('mic', false, store);
  expect(readInput('mic', store)).toBe(false);
  expect(readInput('camera', store)).toBe(true);
  saveInput('mic', true, store);
  expect(readInput('mic', store)).toBe(true);
});
it('allows recording preferences to work when storage is blocked', () => {
  const store = {
    getItem: () => {
      throw new Error('blocked');
    },
    setItem: () => {
      throw new Error('blocked');
    },
  };
  expect(readInput('camera', store)).toBe(true);
  expect(() => saveInput('camera', false, store)).not.toThrow();
});
