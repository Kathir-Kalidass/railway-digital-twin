import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb } from '../src/db.js';
import { makeAudit } from '../src/audit.js';

test('audit writes and lists newest-first with defaults', () => {
  const db = openDb(':memory:');
  const audit = makeAudit(db);
  const a = audit.write({ actor: 'operator', role: 'operator', action: 'RESET', result: 'ACCEPTED', zone: 'zone1' });
  audit.write({ action: 'SPEED', result: 'REJECTED', reason: 'range' });
  assert.ok(a.id);
  assert.equal(a.result, 'ACCEPTED');
  const rows = audit.list();
  assert.equal(rows.length, 2);
  assert.equal(rows[0].action, 'SPEED');
  assert.equal(rows[0].result, 'REJECTED');
});

test('audit.list caps the limit', () => {
  const db = openDb(':memory:');
  const audit = makeAudit(db);
  for (let i = 0; i < 5; i++) audit.write({ action: 'X', result: 'INFO' });
  assert.equal(audit.list(1000).length, 5);
});
