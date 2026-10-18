import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb } from '../src/db.js';
import { makeReplay } from '../src/replay.js';

test('rejects missing and duplicate request ids', () => {
  const replay = makeReplay(openDb(':memory:'));
  assert.equal(replay.check('', { username: 'operator' }).ok, false);
  assert.equal(replay.check('req-1', { username: 'operator', action: 'RESET' }).ok, true);
  const dup = replay.check('req-1', { username: 'operator', action: 'RESET' });
  assert.equal(dup.ok, false);
  assert.match(dup.reason, /duplicate/);
});

test('prune removes entries older than the window', () => {
  const db = openDb(':memory:');
  const replay = makeReplay(db);
  replay.check('old', { username: 'u', action: 'A' });
  db.prepare('UPDATE processed_requests SET received_at = ?').run(new Date(Date.now() - 1000).toISOString());
  assert.equal(replay.prune(1), 1);
});
