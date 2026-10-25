const ISO = (ms) => (ms === null || ms === undefined ? null : new Date(ms).toISOString());
const STORAGE_LIMIT = 200;

export function makeCommandTracker({ ackTimeoutSec = 10, limit = 10, now = () => Date.now() } = {}) {
  const entries = [];

  function issued({ requestId, event, zone, actor, at = now() }) {
    const entry = {
      requestId,
      event,
      zone,
      actor: actor ?? null,
      status: 'PENDING',
      issuedAtMs: at,
      ackAtMs: null,
    };
    entries.push(entry);
    if (entries.length > STORAGE_LIMIT) entries.splice(0, entries.length - STORAGE_LIMIT);
    return entry;
  }

  function acknowledgePending(at) {
    let count = 0;
    for (const e of entries) {
      if (e.status !== 'PENDING') continue;
      if (e.issuedAtMs > at || at - e.issuedAtMs > ackTimeoutSec * 1000) continue;
      e.status = 'ACKNOWLEDGED';
      e.ackAtMs = at;
      count += 1;
    }
    return count;
  }

  function sweep(at) {
    let count = 0;
    for (const e of entries) {
      if (e.status !== 'PENDING') continue;
      if (at - e.issuedAtMs <= ackTimeoutSec * 1000) continue;
      e.status = 'TIMED_OUT';
      e.ackAtMs = null;
      count += 1;
    }
    return count;
  }

  function snapshot() {
    return entries
      .slice(-limit)
      .reverse()
      .map((e) => ({
        requestId: e.requestId,
        event: e.event,
        zone: e.zone,
        actor: e.actor,
        status: e.status,
        issuedAt: ISO(e.issuedAtMs),
        ackAt: ISO(e.ackAtMs),
      }));
  }

  return { issued, acknowledgePending, sweep, snapshot, size: () => entries.length };
}
