export function makeAudit(db) {
  const insert = db.prepare(
    `INSERT INTO audit (time,actor,role,action,zone,target,result,reason,source)
     VALUES (@time,@actor,@role,@action,@zone,@target,@result,@reason,@source)`
  );
  const recent = db.prepare('SELECT * FROM audit ORDER BY id DESC LIMIT ?');
  return {
    write(entry = {}) {
      const row = {
        time: new Date().toISOString(), actor: null, role: null,
        action: 'UNKNOWN', zone: null, target: null, result: 'INFO',
        reason: null, source: null, ...entry,
      };
      const info = insert.run(row);
      return { id: info.lastInsertRowid, ...row };
    },
    list(limit = 100) {
      const n = Math.min(Math.max(Number(limit) || 100, 1), 500);
      return recent.all(n);
    },
  };
}
