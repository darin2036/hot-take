/** Small same-origin control messages only. Media never crosses this channel. */
export const CHANNEL = 'relaytake-controls-v1';
export type Command = 'status' | 'pause' | 'resume' | 'stop' | 'restart';
export interface ControlRequest {
  version: 1;
  requestId: string;
  command: Command;
  owner?: string;
}
export interface Snapshot {
  owner: string;
  state: 'starting' | 'countdown' | 'recording' | 'paused' | 'saving';
  elapsed: number;
  countdown?: number;
  title: string;
}
export function isRequest(value: unknown): value is ControlRequest {
  if (!value || typeof value !== 'object') return false;
  const v = value as Partial<ControlRequest>;
  return (
    v.version === 1 &&
    typeof v.requestId === 'string' &&
    ['status', 'pause', 'resume', 'stop', 'restart'].includes(v.command || '') &&
    (v.command === 'status' || typeof v.owner === 'string')
  );
}
export function isSnapshot(value: unknown): value is Snapshot {
  if (!value || typeof value !== 'object') return false;
  const v = value as Partial<Snapshot>;
  return (
    (v.state !== 'countdown' ||
      (Number.isInteger(v.countdown) && v.countdown! >= 1 && v.countdown! <= 3)) &&
    typeof v.owner === 'string' &&
    typeof v.title === 'string' &&
    typeof v.elapsed === 'number' &&
    Number.isFinite(v.elapsed) &&
    v.elapsed >= 0 &&
    ['starting', 'countdown', 'recording', 'paused', 'saving'].includes(v.state || '')
  );
}
export function requestControl(
  command: Command,
  owner?: string,
  timeout = 1400,
): Promise<Snapshot | null> {
  const channel = new BroadcastChannel(CHANNEL);
  const requestId = crypto.randomUUID();
  return new Promise((resolve) => {
    const complete = (value: Snapshot | null) => {
      clearTimeout(timer);
      channel.close();
      resolve(value);
    };
    const timer = setTimeout(() => complete(null), timeout);
    channel.onmessage = (event) => {
      const data = event.data;
      if (
        data?.version === 1 &&
        data.requestId === requestId &&
        isSnapshot(data.snapshot) &&
        (!owner || data.snapshot.owner === owner)
      )
        complete(data.snapshot);
    };
    channel.postMessage({version: 1, requestId, command, owner} satisfies ControlRequest);
  });
}
