import test from 'node:test';
import assert from 'node:assert';
import { restoreSpeed } from '../src/speed_restore.js';

test('restores saved speed when finite and positive', () => {
  const t = { id: 'T1', commandedSpeedKmh: null };
  let log = null;
  const r = restoreSpeed(t, 30, { reason: 'MEET_HOLD_RELEASE', fallbackKmh: 48, onRestore: (e) => (log = e) });
  assert.strictEqual(r, 30);
  assert.strictEqual(t.commandedSpeedKmh, 30);
  assert.strictEqual(log, null); // no fallback event for a valid restore
});

for (const [label, saved] of [['null', null], ['zero', 0], ['negative', -5], ['non-finite', NaN]]) {
  test(`falls back to 48 with SPEED_RESTORED_FALLBACK when saved is ${label}`, () => {
    const t = { id: 'T3', commandedSpeedKmh: saved };
    const events = [];
    const r = restoreSpeed(t, saved, { reason: 'WRONG_LINE_FINISH', fallbackKmh: 48, onRestore: (e) => events.push(e) });
    assert.strictEqual(r, 48);
    assert.strictEqual(t.commandedSpeedKmh, 48);
    assert.strictEqual(events.length, 1);
    assert.strictEqual(events[0].type, 'SPEED_RESTORED_FALLBACK');
    assert.strictEqual(events[0].trainId, 'T3');
    assert.strictEqual(events[0].reason, 'WRONG_LINE_FINISH');
    assert.strictEqual(events[0].restoredKmh, 48);
    assert.strictEqual(events[0].attemptedSavedKmh, saved === null ? null : saved);
    assert.ok(events[0].timestamp);
  });
}
