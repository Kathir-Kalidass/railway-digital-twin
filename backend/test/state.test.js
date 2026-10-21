import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeState } from '../src/state.js';
import { buildTopology } from '../src/railway.js';

const config = { zones: ['zone1', 'zone2'] };
const env = (zone, event) => ({ request_id: `${event}-${zone}`, zone, event, timestamp: new Date().toISOString(), source: 'dashboard', payload: {} });

const fleetConfig = (trains = [
  { id: 'T1', line: 'UP', direction: 'UP', startBlock: 0, startOffsetM: 0, lengthM: 60 },
  { id: 'T3', line: 'DOWN', direction: 'DOWN', startBlock: 0, startOffsetM: 0, lengthM: 60 },
]) => ({
  zones: ['zone1', 'zone2'],
  topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, lineLengthM: { UP: 753.9822, DOWN: 728.8495 }, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'x', upIndex: 2, downIndex: 2, dwellSec: 20 }, crossovers: [
    { id: 'X-UP-DOWN', from: 'UP-B2', to: 'DOWN-B2' },
    { id: 'X-DOWN-UP', from: 'DOWN-B2', to: 'UP-B2' },
  ] },
  trains,
  simulation: { tickMs: 500, lookaheadBlocks: 2, cautionSpeedKmh: 30, brakeMps2: 2.0, accelMps2: 0.6, defaultTargetSpeedKmh: 48 },
});
const fleet = (trains) => {
  const c = fleetConfig(trains);
  return makeState({ config: c, topology: buildTopology(c) });
};

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

test('fleet snapshot exposes two trains, blocks, lines, station and routes', () => {
  const snap = fleet().snapshot();
  assert.deepEqual(snap.trains.map((t) => t.id), ['T1', 'T3']);
  assert.equal(snap.lines.length, 2);
  assert.equal(snap.blocks.length, 10);
  assert.equal(snap.station.blocks.UP, 'UP-B2');
  assert.equal(snap.train.id, 'T1');
  assert.equal(snap.blocks.find((b) => b.id === 'UP-B0').occupiedBy, 'T1');
  assert.equal(snap.blocks.find((b) => b.id === 'UP-B0').signal, 'RED');
  assert.equal(snap.blocks.find((b) => b.id === 'UP-B3').signal, 'YELLOW');
  assert.deepEqual(snap.zones.zone1.blocks.sort(), ['DOWN-B0', 'DOWN-B1', 'DOWN-B2', 'UP-B0', 'UP-B1', 'UP-B2']);
  assert.equal(snap.routes.available.length, 2);
  assert.equal(snap.routes.active, null);
});

test('fleet tick advances trains and respects broker connectivity', () => {
  const s = fleet();
  const before = s.snapshot().trains[0].offsetM;
  s.setBrokerConnected(false);
  s.tick(1);
  assert.equal(s.snapshot().trains[0].offsetM, before);
  s.setBrokerConnected(true);
  s.tick(1);
  assert.ok(s.snapshot().trains[0].offsetM > before);
});

test('fleet requestRoute grants once and then rejects a conflicting route', () => {
  const s = fleet([
    { id: 'T1', line: 'UP', direction: 'UP', startBlock: 2, startOffsetM: 0, lengthM: 60 },
    { id: 'T3', line: 'DOWN', direction: 'DOWN', startBlock: 0, startOffsetM: 0, lengthM: 60 },
  ]);
  const granted = s.requestRoute({ trainId: 'T1', routeId: 'X-UP-DOWN' });
  assert.equal(granted.ok, true);
  const snap = s.snapshot();
  assert.equal(snap.trains[0].line, 'DOWN');
  assert.equal(snap.trains[0].block, 'DOWN-B2');
  assert.equal(snap.routes.active.routeId, 'X-UP-DOWN');
  const second = s.requestRoute({ trainId: 'T3', routeId: 'X-DOWN-UP' });
  assert.equal(second.ok, false);
});

test('fleet hazard rejects a crossover and per-train speed is validated', () => {
  const s = fleet([{ id: 'T1', line: 'UP', direction: 'UP', startBlock: 2, startOffsetM: 0, lengthM: 60 }]);
  s.setWildlife('zone1', true);
  assert.equal(s.requestRoute({ trainId: 'T1', routeId: 'X-UP-DOWN' }).ok, false);
  s.setWildlife('zone1', false);
  s.applyCommand(env('zone1', 'RESET'));
  assert.equal(s.applySpeed({ trainId: 'T1', speedKmh: 0 }).ok, true);
  assert.equal(s.snapshot().trains[0].targetSpeedKmh, 0);
  assert.equal(s.applySpeed({ trainId: 'NOPE', speedKmh: 10 }).ok, false);
});

test('legacy zone-only state keeps its shape without fleet fields', () => {
  const snap = makeState({ config }).snapshot();
  assert.equal(snap.trains, undefined);
  assert.equal(snap.routes, undefined);
  assert.equal(snap.train.speedKmh, 48);
});
