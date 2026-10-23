import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeCommandTracker } from '../src/command_tracker.js';

const fakeNow = () => fakeNow.value;
fakeNow.value = 0;
const iso = (ms) => new Date(ms).toISOString();

test('issued command is PENDING and snapshot is newest-first', () => {
  const tracker = makeCommandTracker({ ackTimeoutSec: 10 });
  tracker.issued({ requestId: 'req-1', event: 'RESET', zone: 'zone1', actor: 'operator', at: 1000 });
  tracker.issued({ requestId: 'req-2', event: 'WILDLIFE_DETECTED', zone: 'zone1', actor: 'operator', at: 2000 });
  const snap = tracker.snapshot();
  assert.equal(snap.length, 2);
  assert.equal(snap[0].requestId, 'req-2');
  assert.equal(snap[1].requestId, 'req-1');
  assert.equal(snap[0].status, 'PENDING');
  assert.equal(snap[0].issuedAt, iso(2000));
  assert.equal(snap[0].ackAt, null);
});

test('acknowledgePending acks a command issued before the telemetry and within window', () => {
  const tracker = makeCommandTracker({ ackTimeoutSec: 10 });
  tracker.issued({ requestId: 'req-1', event: 'RESET', zone: 'zone1', actor: 'operator', at: 1000 });
  const acked = tracker.acknowledgePending(6000);
  assert.equal(acked, 1);
  const [entry] = tracker.snapshot();
  assert.equal(entry.status, 'ACKNOWLEDGED');
  assert.equal(entry.ackAt, iso(6000));
});

test('acknowledgePending does not ack commands issued after the telemetry instant', () => {
  const tracker = makeCommandTracker({ ackTimeoutSec: 10 });
  // telemetry instance at t=6000: nothing issued yet
  assert.equal(tracker.acknowledgePending(6000), 0);
  tracker.issued({ requestId: 'req-1', event: 'RESET', zone: 'zone1', actor: 'operator', at: 7000 });
  const [entry] = tracker.snapshot();
  assert.equal(entry.status, 'PENDING');
});

test('telemetry older than the ack window does not ack; the sweeper times the command out', () => {
  const tracker = makeCommandTracker({ ackTimeoutSec: 10 });
  tracker.issued({ requestId: 'req-1', event: 'RESET', zone: 'zone1', actor: 'operator', at: 1000 });
  assert.equal(tracker.acknowledgePending(12_000), 0);
  assert.equal(tracker.snapshot()[0].status, 'PENDING');
  assert.equal(tracker.sweep(12_000), 1);
  assert.equal(tracker.snapshot()[0].status, 'TIMED_OUT');
  assert.equal(tracker.snapshot()[0].ackAt, null);
});

test('sweep leaves acknowledged entries untouched', () => {
  const tracker = makeCommandTracker({ ackTimeoutSec: 10 });
  tracker.issued({ requestId: 'req-1', event: 'RESET', zone: 'zone1', actor: 'operator', at: 1000 });
  tracker.acknowledgePending(6000);
  tracker.issued({ requestId: 'req-2', event: 'RESET', zone: 'zone1', actor: 'operator', at: 6500 });
  assert.equal(tracker.sweep(25_000), 1);
  const snap = tracker.snapshot();
  assert.equal(snap.find((e) => e.requestId === 'req-1').status, 'ACKNOWLEDGED');
  assert.equal(snap.find((e) => e.requestId === 'req-2').status, 'TIMED_OUT');
});

test('snapshot caps at limit and renders ISO timestamps', () => {
  const tracker = makeCommandTracker({ ackTimeoutSec: 10, limit: 3 });
  for (let i = 1; i <= 5; i++) {
    tracker.issued({ requestId: `req-${i}`, event: 'RESET', zone: 'zone1', actor: 'operator', at: i * 1000 });
  }
  const snap = tracker.snapshot();
  assert.equal(snap.length, 3);
  assert.deepEqual(snap.map((e) => e.requestId), ['req-5', 'req-4', 'req-3']);
  assert.equal(snap[0].issuedAt, iso(5000));
  assert.ok(!Number.isNaN(Date.parse(snap[0].issuedAt)));
});

test('injected now() is honored by issued without explicit at', () => {
  fakeNow.value = 42_000;
  const tracker = makeCommandTracker({ ackTimeoutSec: 10, now: fakeNow });
  const entry = tracker.issued({ requestId: 'req-1', event: 'RESET', zone: 'zone1', actor: 'operator' });
  assert.equal(entry.issuedAtMs, 42_000);
  assert.equal(entry.status, 'PENDING');
  assert.equal(tracker.snapshot()[0].issuedAt, iso(42_000));
});
