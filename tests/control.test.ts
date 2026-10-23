import {describe, it, expect} from 'vitest';
import {isRequest, isSnapshot, requestControl, CHANNEL} from '../src/control';
describe('popup control protocol', () => {
  it('rejects malformed commands and commands without a target owner', () => {
    expect(isRequest({version: 1, requestId: '1', command: 'stop'})).toBe(false);
    expect(isRequest({version: 2, requestId: '1', command: 'status'})).toBe(false);
    expect(isRequest({version: 1, requestId: '1', command: 'delete', owner: 'a'})).toBe(false);
    expect(isRequest({version: 1, requestId: '1', command: 'pause', owner: 'a'})).toBe(true);
    expect(isRequest({version: 1, requestId: '1', command: 'restart', owner: 'a'})).toBe(true);
    expect(isRequest({version: 1, requestId: '1', command: 'restart'})).toBe(false);
  });
  it('rejects invalid snapshots', () => {
    expect(isSnapshot({owner: 'a', title: 'x', state: 'countdown', countdown: 3, elapsed: 0})).toBe(
      true,
    );
    expect(isSnapshot({owner: 'a', title: 'x', state: 'countdown', countdown: 4, elapsed: 0})).toBe(
      false,
    );
    expect(isSnapshot({owner: 'a', title: 'x', state: 'recording', elapsed: Infinity})).toBe(false);
    expect(isSnapshot({owner: 'a', title: 'x', state: 'recording', elapsed: -1})).toBe(false);
  });
  it('only accepts acknowledgements from the targeted owner', async () => {
    const owner = new BroadcastChannel(CHANNEL);
    owner.onmessage = (event) => {
      const request = event.data;
      owner.postMessage({
        version: 1,
        requestId: request.requestId,
        snapshot: {owner: 'other', state: 'recording', title: 'Other', elapsed: 5},
      });
      owner.postMessage({
        version: 1,
        requestId: request.requestId,
        snapshot: {owner: 'right', state: 'paused', title: 'Test', elapsed: 10},
      });
    };
    try {
      expect(await requestControl('pause', 'right', 500)).toMatchObject({
        owner: 'right',
        state: 'paused',
      });
    } finally {
      owner.close();
    }
  });
  it('returns unavailable when no owner responds', async () => {
    expect(await requestControl('status', undefined, 20)).toBeNull();
  });
});
