// In-memory store with JSON-file persistence. One file per collection under
// DATA_DIR. Writes are synchronous atomic replaces (tmp + rename) so a crash
// or restart never observes a half-written file, and quota survives restarts.
import fs from 'node:fs';
import path from 'node:path';

export const COLLECTIONS = /** @type {const} */ ([
  'sessions',
  'usage',
  'entitlements',
  'idempotency',
  'receipts',
  'spend',
  'turns',
  'meta',
]);

/**
 * @param {{dataDir: string, persist?: boolean}} opts
 */
export function createStore({ dataDir, persist = true }) {
  /** @type {Record<string, Map<string, any>>} */
  const maps = {};
  for (const name of COLLECTIONS) maps[name] = new Map();

  if (persist) {
    fs.mkdirSync(dataDir, { recursive: true });
    for (const name of COLLECTIONS) {
      const file = fileFor(name);
      if (!fs.existsSync(file)) continue;
      try {
        const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
        if (parsed && typeof parsed === 'object') {
          for (const [k, v] of Object.entries(parsed)) maps[name].set(k, v);
        }
      } catch {
        // Corrupt file: quarantine it and start that collection empty (safe defaults).
        try {
          fs.renameSync(file, `${file}.corrupt-${Date.now()}`);
        } catch {
          /* ignore */
        }
      }
    }
  }

  /** @param {string} name */
  function fileFor(name) {
    return path.join(dataDir, `${name}.json`);
  }

  /** @param {string} name */
  function flush(name) {
    if (!persist) return;
    const file = fileFor(name);
    const tmp = `${file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(Object.fromEntries(maps[name])), 'utf8');
    fs.renameSync(tmp, file);
  }

  /** @param {string} name */
  function collection(name) {
    const map = maps[name];
    if (!map) throw new Error(`unknown collection ${name}`);
    return {
      /** @param {string} key */
      get: (key) => map.get(key),
      /** @param {string} key */
      has: (key) => map.has(key),
      /** @param {string} key @param {any} value */
      set: (key, value) => {
        map.set(key, value);
        flush(name);
        return value;
      },
      /** @param {string} key */
      delete: (key) => {
        const had = map.delete(key);
        if (had) flush(name);
        return had;
      },
      values: () => Array.from(map.values()),
      entries: () => Array.from(map.entries()),
      size: () => map.size,
      clear: () => {
        map.clear();
        flush(name);
      },
    };
  }

  return {
    dataDir,
    sessions: collection('sessions'),
    usage: collection('usage'),
    entitlements: collection('entitlements'),
    idempotency: collection('idempotency'),
    receipts: collection('receipts'),
    spend: collection('spend'),
    turns: collection('turns'),
    meta: collection('meta'),
    flushAll: () => COLLECTIONS.forEach(flush),
  };
}
