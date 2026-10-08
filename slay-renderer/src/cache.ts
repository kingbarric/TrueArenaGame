/** Cache immutable, versioned GLBs locally; GPU objects are still freed on unequip. */
import { inspectGlb, MAX_ASSET_BYTES as MAX_BYTES } from './glb';
const open = () => new Promise<IDBDatabase>((resolve, reject) => {
  const request = indexedDB.open('slay-assets-v1', 1);
  request.onupgradeneeded = () => request.result.createObjectStore('glbs', {keyPath: 'url'});
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});
const request = <T>(r: IDBRequest<T>) => new Promise<T>((resolve, reject) => {
  r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
});
export async function assetBytes(url: string): Promise<ArrayBuffer> {
  let db: IDBDatabase | undefined;
  try {
    db = await open();
    const cached = await request(db.transaction('glbs').objectStore('glbs').get(url));
    if(cached) { inspectGlb(cached.bytes); db.close(); return cached.bytes; }
  } catch { /* Private browsing / full storage still permits network rendering. */ }
  try {
    const response = await fetch(url, {signal: AbortSignal.timeout(20000)});
    if(!response.ok) throw Error('Could not load asset: HTTP '+response.status);
    const bytes = await response.arrayBuffer();
    inspectGlb(bytes);
    if(db) {
      try {
        const records = await request(db.transaction('glbs').objectStore('glbs').getAll());
        let total = bytes.byteLength + records.reduce((sum, r) => sum+r.bytes.byteLength, 0);
        const transaction = db.transaction('glbs', 'readwrite'), store = transaction.objectStore('glbs');
        for(const record of records.sort((a,b) => a.savedAt-b.savedAt)) {
          if(total <= MAX_BYTES) break;
          store.delete(record.url); total -= record.bytes.byteLength;
        }
        store.put({url, bytes, savedAt: Date.now()});
      } catch { /* Cache is an optimization, not an asset-loading prerequisite. */ }
    }
    return bytes;
  } finally { db?.close(); }
}
