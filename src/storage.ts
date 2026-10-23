export interface Recording {
  id: string;
  title: string;
  created: number;
  mime: string;
  size: number;
  chunks: number;
  duration: number;
  status: 'recording' | 'ready' | 'interrupted';
}
interface Chunk {
  recordingId: string;
  sequence: number;
  blob: Blob;
}
let database: Promise<IDBDatabase> | undefined;
function request<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}
function done(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onabort = () => reject(tx.error || new Error('Storage transaction aborted'));
    tx.onerror = () => {};
  });
}
export function openDB() {
  return (database ??= new Promise<IDBDatabase>((resolve, reject) => {
    const req = indexedDB.open('relaytake', 2);
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains('recordings'))
        req.result.createObjectStore('recordings', {keyPath: 'id'});
      if (!req.result.objectStoreNames.contains('chunks'))
        req.result.createObjectStore('chunks', {keyPath: ['recordingId', 'sequence']});
      if (!req.result.objectStoreNames.contains('thumbnails'))
        req.result.createObjectStore('thumbnails');
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  }));
}
export async function save(recording: Recording) {
  const db = await openDB();
  const tx = db.transaction('recordings', 'readwrite');
  const completion = done(tx);
  tx.objectStore('recordings').put(recording);
  await completion;
}
export async function list(): Promise<Recording[]> {
  const db = await openDB();
  return (
    (await request(db.transaction('recordings').objectStore('recordings').getAll())) as Recording[]
  ).sort((a, b) => b.created - a.created);
}
export async function append(id: string, blob: Blob) {
  const db = await openDB();
  const tx = db.transaction(['recordings', 'chunks'], 'readwrite');
  const completion = done(tx);
  const store = tx.objectStore('recordings');
  const req = store.get(id);
  req.onsuccess = () => {
    const row = req.result as Recording | undefined;
    if (!row || row.status !== 'recording') {
      tx.abort();
      return;
    }
    tx.objectStore('chunks').put({recordingId: id, sequence: row.chunks, blob});
    store.put({...row, chunks: row.chunks + 1, size: row.size + blob.size});
  };
  await completion;
}
export async function finalize(id: string, duration: number, interrupted = false) {
  const db = await openDB();
  const tx = db.transaction('recordings', 'readwrite');
  const completion = done(tx);
  const store = tx.objectStore('recordings');
  const req = store.get(id);
  req.onsuccess = () => {
    if (req.result)
      store.put({...req.result, duration, status: interrupted ? 'interrupted' : 'ready'});
  };
  await completion;
}
export async function readBlob(row: Recording): Promise<Blob> {
  const db = await openDB();
  const chunks = (await request(
    db
      .transaction('chunks')
      .objectStore('chunks')
      .getAll(IDBKeyRange.bound([row.id, 0], [row.id, Number.MAX_SAFE_INTEGER])),
  )) as Chunk[];
  return new Blob(
    chunks.map((c) => c.blob),
    {type: row.mime},
  );
}
export async function remove(id: string) {
  const db = await openDB();
  const tx = db.transaction(['recordings', 'chunks', 'thumbnails'], 'readwrite');
  const completion = done(tx);
  tx.objectStore('recordings').delete(id);
  tx.objectStore('thumbnails').delete(id);
  tx.objectStore('chunks').delete(IDBKeyRange.bound([id, 0], [id, Number.MAX_SAFE_INTEGER]));
  await completion;
}

export async function getThumbnail(id: string): Promise<Blob | undefined> {
  const db = await openDB();
  return request(db.transaction('thumbnails').objectStore('thumbnails').get(id));
}
export async function saveThumbnail(id: string, blob: Blob) {
  const db = await openDB();
  const tx = db.transaction(['recordings', 'thumbnails'], 'readwrite');
  const completion = done(tx);
  const req = tx.objectStore('recordings').get(id);
  req.onsuccess = () => {
    if (req.result) tx.objectStore('thumbnails').put(blob, id);
  };
  await completion;
}
/** Read only enough leading media to decode a poster, never the whole take. */
export async function readPrefix(row: Recording, limit = 8 * 1024 * 1024): Promise<Blob> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const parts: Blob[] = [];
    let size = 0;
    const tx = db.transaction('chunks');
    const cursor = tx
      .objectStore('chunks')
      .openCursor(IDBKeyRange.bound([row.id, 0], [row.id, Number.MAX_SAFE_INTEGER]));
    cursor.onerror = () => reject(cursor.error);
    cursor.onsuccess = () => {
      const item = cursor.result;
      if (!item || size >= limit) {
        resolve(new Blob(parts, {type: row.mime}));
        return;
      }
      const blob = (item.value as Chunk).blob.slice(0, limit - size);
      parts.push(blob);
      size += blob.size;
      item.continue();
    };
  });
}
