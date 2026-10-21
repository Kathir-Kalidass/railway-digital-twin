import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeState } from '../src/state.js';

const config = { zones: ['zone1', 'zone2'] };
const env = (zone, event) => ({ request_id: `${event}-${zone}`, zone, event, timestamp: new Date().toISOString(), source: 'dashboard', payload: {} });

test('wildlife in zone1 makes zone1 RED and zone2 YELLOW, zones independent', () => {
  const s = makeState({ config });
  assert.equal(s.applyCommand(env('zone1', 'WILDLIFE_DETECTED')).ok, true);
  const snap = s.snapshot();
  assert.equal(snap.zones.zone1.signal, 'RED');
  assert.equal(snap.zones.zone2.signal, 'YELLOW');
  assert.equal(snap.zones.zone2.wildlifeDetected, false);
  assert.equal(snap.overall, 'HAZARD');
});

test('clearing wildlife requires reset and stays restrictive', () => {
  const s = makeState({ config });
  s.applyCommand(env('zone1', 'WILDLIFE_DETECTED'));
  s.applyCommand(env('zone1', 'WILDLIFE_CLEARED'));
  let snap = s.snapshot();
  assert.equal(snap.zones.zone1.signal, 'RED');
  assert.equal(snap.overall, 'RECOVERY_REQUIRED');
  assert.equal(s.applyCommand(env('zone1', 'RESET')).ok, true);
  snap = s.snapshot();
  assert.equal(snap.zones.zone1.signal, 'GREEN');
  assert.equal(snap.overall, 'NORMAL');
});

test('telemetry detection sets hazard and clear requires reset', () => {
  const s = makeState({ config });
  s.setWildlife('zone1', true);
  let snap = s.snapshot();
  assert.equal(snap.zones.zone1.signal, 'RED');
  assert.equal(snap.zones.zone1.targetSpeedKmh, 0);
  assert.equal(snap.overall, 'HAZARD');

  s.setWildlife('zone1', false);
  snap = s.snapshot();
  assert.equal(snap.zones.zone1.signal, 'RED');
  assert.equal(snap.overall, 'RECOVERY_REQUIRED');
  assert.equal(s.applyCommand(env('zone1', 'RESET')).ok, true);
  snap = s.snapshot();
  assert.equal(snap.zones.zone1.signal, 'GREEN');
  assert.equal(snap.overall, 'NORMAL');
});

test('reset is rejected while hazard active', () => {
  const s = makeState({ config });
  s.applyCommand(env('zone2', 'SENSOR_FAULT'));
  const r = s.applyCommand(env('zone2', 'RESET'));
  assert.equal(r.ok, false);
  assert.match(r.reason, /reject/i);
});

test('sensor restore then reset returns to normal', () => {
  const s = makeState({ config });
  s.applyCommand(env('zone2', 'SENSOR_FAULT'));
  s.applyCommand(env('zone2', 'SENSOR_RESTORED'));
  assert.equal(s.snapshot().zones.zone2.signal, 'RED');
  s.applyCommand(env('zone2', 'RESET'));
  assert.equal(s.snapshot().overall, 'NORMAL');
});

test('per-zone speed and stopping distance', () => {
  const s = makeState({ config });
  assert.equal(s.applySpeed({ zone: 'zone1', speedKmh: 0 }).ok, true);
  const snap = s.snapshot();
  assert.equal(snap.zones.zone1.targetSpeedKmh, 0);
  s.applyTelemetry('zone1', { speedKmh: 36, trainPresent: true });
  assert.equal(s.snapshot().train.speedKmh, 36);
  assert.ok(s.snapshot().train.stoppingDistanceM > 0);
});

test('broker disconnect forces restrictive overall state', () => {
  const s = makeState({ config });
  s.setBrokerConnected(false);
  assert.equal(s.snapshot().overall, 'COMM_LOST');
  s.setBrokerConnected(true);
  assert.equal(s.snapshot().overall, 'NORMAL');
});
