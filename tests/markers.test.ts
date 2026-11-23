import 'fake-indexeddb/auto';
import {describe, it, expect} from 'vitest';
import {addMarker, chaptersVtt, cleanMarkers, timestamp, timestampList} from '../src/markers';
import {filename, importMime, safeTitle} from '../src/core';
import {isRequest} from '../src/control';
import {finalize, importBlob, list, readBlob, save} from '../src/storage';

describe('chapter markers', () => {
  it('adds numbered markers in active time and ignores near-duplicates', () => {
    let m = addMarker([], 0);
    m = addMarker(m, 12340);
    expect(addMarker(m, 12500)).toBe(m);
    m = addMarker(m, 65000, '  Deploy  ');
    expect(m).toEqual([
      {time: 0, title: 'Marker 1'},
      {time: 12.3, title: 'Marker 2'},
      {time: 65, title: 'Deploy'},
    ]);
  });
  it('formats timestamps and a chapters file', () => {
    expect(timestamp(75)).toBe('1:15');
    expect(timestamp(3725)).toBe('1:02:05');
    const m = [
      {time: 0, title: 'Intro'},
      {time: 30, title: 'a --> b'},
    ];
    expect(timestampList(m)).toBe('0:00 Intro\n0:30 a --> b');
    expect(chaptersVtt(m, 45)).toBe(
      'WEBVTT\n\n00:00:00.000 --> 00:00:30.000\nIntro\n\n00:00:30.000 --> 00:00:45.000\na → b\n',
    );
  });
  it('drops malformed stored markers', () => {
    expect(
      cleanMarkers([{time: 5, title: 'b'}, {time: -1, title: 'x'}, null, {time: 1, title: 'a'}, {title: 'z'}]),
    ).toEqual([
      {time: 1, title: 'a'},
      {time: 5, title: 'b'},
    ]);
    expect(cleanMarkers('nope')).toEqual([]);
  });
  it('accepts the marker control command', () => {
    expect(isRequest({version: 1, requestId: '1', command: 'marker', owner: 'a'})).toBe(true);
    expect(isRequest({version: 1, requestId: '1', command: 'marker'})).toBe(false);
  });
  it('keeps markers when a take is finalized', async () => {
    await save({id: 'm1', title: 'T', created: 1, mime: 'video/webm', size: 0, chunks: 0, duration: 0, status: 'recording'});
    await finalize('m1', 5000, false, [{time: 2, title: 'Marker 1'}]);
    expect((await list()).find((r) => r.id === 'm1')!.markers).toEqual([{time: 2, title: 'Marker 1'}]);
  });
});
describe('video import', () => {
  it('recognizes supported containers and names files', () => {
    expect(importMime('a.MOV', '')).toBe('video/quicktime');
    expect(importMime('a.m4v', '')).toBe('video/mp4');
    expect(importMime('a.mkv', 'video/x-matroska')).toBe('');
    expect(filename('Clip', 'video/quicktime')).toBe('Clip.mov');
    expect(safeTitle('a/b')).toBe('a-b');
  });
  it('stores an imported file in slices as a ready take', async () => {
    const id = await importBlob(new Blob(['hello world']), 'Imported', 'video/mp4', 3000);
    const row = (await list()).find((r) => r.id === id)!;
    expect(row).toMatchObject({status: 'ready', duration: 3000, size: 11, title: 'Imported'});
    expect(await (await readBlob(row)).text()).toBe('hello world');
  });
});
