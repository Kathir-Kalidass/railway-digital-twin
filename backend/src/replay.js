export function makeReplay(db) {
  const insert = db.prepare(
    'INSERT INTO processed_requests (request_id,username,action,received_at) VALUES (?,?,?,?)'
  );
  const exists = db.prepare('SELECT 1 AS hit FROM processed_requests WHERE request_id = ?');
  const deleteOld = db.prepare('DELETE FROM processed_requests WHERE received_at < ?');
  return {
    check(requestId, { username = '', action = '' } = {}) {
      const id = String(requestId || '');
      if (!id) return { ok: false, reason: 'missing request_id' };
      if (exists.get(id)) return { ok: false, reason: 'duplicate request_id' };
      insert.run(id, String(username), String(action), new Date().toISOString());
      return { ok: true };
    },
    prune(maxAgeMs = 24 * 3600 * 1000) {
      return deleteOld.run(new Date(Date.now() - maxAgeMs).toISOString()).changes;
    },
  };
}
