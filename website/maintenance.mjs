// Retry failures and share in-flight work; successful maintenance expires on demand.
export function createMaintenance(task, { intervalMs = Infinity, now = Date.now } = {}) {
  let pending;
  let completedAt;
  return function run() {
    if (pending) return pending;
    if (completedAt !== undefined && now() - completedAt < intervalMs) return Promise.resolve();
    pending = Promise.resolve().then(task).then(() => { completedAt = now(); }).finally(() => { pending = undefined; });
    return pending;
  };
}

// Keep file pruning and appends in one queue so a rewrite cannot lose a new record.
export function createSerialQueue() {
  let tail = Promise.resolve();
  return (task) => {
    const result = tail.then(task);
    tail = result.catch(() => {});
    return result;
  };
}

export const PRUNE_INTERVAL_MS = 24 * 60 * 60 * 1000;
