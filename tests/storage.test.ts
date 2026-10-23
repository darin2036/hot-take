import 'fake-indexeddb/auto';
import {describe, it, expect} from 'vitest';
import {append, finalize, list, readBlob, remove, save, type Recording} from '../src/storage';
import {ActiveClock, filename} from '../src/core';
import {supportedMime} from '../src/capture';
const row = (id: string): Recording => ({
  id,
  title: 'Test',
  created: 1,
  mime: 'video/webm',
  size: 0,
  chunks: 0,
  duration: 0,
  status: 'recording',
});
describe('durable recordings', () => {
  it('commits bytes and metadata together, preserves order, and finalizes', async () => {
    await save(row('ordered'));
    await append('ordered', new Blob(['first']));
    await append('ordered', new Blob(['second']));
    await finalize('ordered', 1200);
    const result = (await list()).find((r) => r.id === 'ordered')!;
    expect(result).toMatchObject({size: 11, chunks: 2, duration: 1200, status: 'ready'});
    expect(await (await readBlob(result)).text()).toBe('firstsecond');
    await expect(append('ordered', new Blob(['late']))).rejects.toThrow();
    expect((await list()).find((r) => r.id === 'ordered')!.size).toBe(11);
  });
  it('retains committed chunks after interruption and deletes only selected take', async () => {
    await save(row('crashed'));
    await append('crashed', new Blob(['saved']));
    await finalize('crashed', 0, true);
    const result = (await list()).find((r) => r.id === 'crashed')!;
    expect(result.status).toBe('interrupted');
    expect(await (await readBlob(result)).text()).toBe('saved');
    await remove('crashed');
    expect((await list()).some((r) => r.id === 'crashed')).toBe(false);
    expect((await readBlob(result)).size).toBe(0);
    expect((await list()).some((r) => r.id === 'ordered')).toBe(true);
  });
  it('rejects writes without metadata', async () => {
    await expect(append('missing', new Blob(['lost']))).rejects.toThrow();
  });
});
it('excludes paused time and ignores duplicate transitions', () => {
  let now = 0;
  const clock = new ActiveClock(() => now);
  clock.resume();
  now = 100;
  clock.resume();
  clock.pause();
  now = 900;
  clock.pause();
  expect(clock.elapsed).toBe(100);
  clock.resume();
  now = 1000;
  expect(clock.elapsed).toBe(200);
});
it('uses correct container suffix and safe filenames', () => {
  expect(filename('demo / a:b', 'video/webm;codecs=vp8,opus')).toBe('demo - a-b.webm');
  expect(filename(' ', 'video/mp4')).toBe('Recording.mp4');
});

it('bounds thumbnail media reads and removes cached images with their take', async () => {
  const {readPrefix, saveThumbnail, getThumbnail} = await import('../src/storage');
  await save(row('poster'));
  await append('poster', new Blob(['abcdef']));
  await append('poster', new Blob(['ghijkl']));
  expect(await (await readPrefix(row('poster'), 8)).text()).toBe('abcdefgh');
  await saveThumbnail('poster', new Blob(['image'], {type: 'image/webp'}));
  expect((await getThumbnail('poster'))?.size).toBe(5);
  await remove('poster');
  expect(await getThumbnail('poster')).toBeUndefined();
  await saveThumbnail('poster', new Blob(['late']));
  expect(await getThumbnail('poster')).toBeUndefined();
});

it('prefers MP4 and falls back to WebM', () => {
  expect(supportedMime(() => true)).toMatch(/^video\/mp4/);
  expect(supportedMime((type) => type.startsWith('video/webm;codecs=vp8'))).toBe(
    'video/webm;codecs=vp8,opus',
  );
  expect(supportedMime(() => false)).toBe('');
});
