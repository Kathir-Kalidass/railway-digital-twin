import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeMeetScheduler } from '../src/meets.js';

function makeWorld(overrides = {}) {
  const lineBlocks = (line) => Array.from({ length: 5 }, (_, i) => `${line}-B${i}`);
  const topology = {
    lines: [
      { id: 'UP', blocks: lineBlocks('UP') },
      { id: 'DOWN', blocks: lineBlocks('DOWN') },
    ],
    blocks: ['UP', 'DOWN'].flatMap((line) =>
      lineBlocks(line).map((id, index) => ({ id, line, index, zone: index < 3 ? 'zone1' : 'zone2' }))),
    station: { id: 'station', blocks: { UP: 'UP-B2', DOWN: 'DOWN-B2' } },
    crossovers: [
      { id: 'X-UP-DOWN', from: 'UP-B2', to: 'DOWN-B2' },
      { id: 'X-DOWN-UP', from: 'DOWN-B2', to: 'UP-B2' },
    ],
  };
  const zones = {
    zone1: { wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' },
    zone2: { wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' },
  };
  const trains = overrides.trains || [
    { id: 'T1', line: 'UP', block: 'UP-B2', offsetM: 10, speedKmh: 0, commandedSpeedKmh: null },
    { id: 'T3', line: 'DOWN', block: 'DOWN-B1', offsetM: 100, speedKmh: 48, commandedSpeedKmh: null },
  ];
  const routeCalls = [];
  let activeRoute = null;
  let hazardBlock = overrides.hazardBlock || null;
  const routes = {
    requestRoute({ trainId, routeId }) {
      routeCalls.push({ trainId, routeId });
      if (overrides.rejectRoutes) return { ok: false, reason: 'rejected' };
      const definition = topology.crossovers.find((r) => r.id === routeId);
      const train = trains.find((t) => t.id === trainId);
      if (!definition || !train || train.block !== definition.from) {
        return { ok: false, reason: 'not at from block' };
      }
      if (trains.some((t) => t.id !== trainId && t.block === definition.to)) {
        return { ok: false, reason: 'destination occupied' };
      }
      activeRoute = { routeId, trainId, from: definition.from, to: definition.to };
      train.line = definition.to.split('-')[0];
      train.block = definition.to;
      train.offsetM = 0;
      return { ok: true, route: { ...activeRoute } };
    },
    activeRoute: () => (activeRoute ? { ...activeRoute } : null),
    clear: () => { activeRoute = null; },
  };
  const meets = {
    enabled: true,
    seed: 42,
    minGapSec: 0.5,
    maxGapSec: 0.5,
    stationWaitSec: 10,
    holdOffsetM: 80,
    minHoldSec: 1,
    maxHoldSec: 2,
    meetChance: 1,
    crossoverChance: 0,
    holdTimeoutSec: 5,
    ...overrides.meets,
  };
  const scheduler = makeMeetScheduler({
    topology,
    trains,
    zones,
    routes,
    config: { meets },
    hasActiveHazard: (id) => hazardBlock === id,
  });
  return {
    topology,
    zones,
    trains,
    routes,
    routeCalls,
    scheduler,
    __clearHazard: () => { hazardBlock = null; },
  };
}

test('a meet holds one train at the station while the other moves', () => {
  const w = makeWorld({ meets: { crossoverChance: 0 } });
  w.scheduler.tick(0.5);
  w.scheduler.tick(0.5);
  let snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'HOLDING');
  const holder = w.trains.find((t) => t.id === snap.active.holderId);
  const other = w.trains.find((t) => t.id !== holder.id);
  assert.equal(holder.commandedSpeedKmh, 0);
  assert.equal(other.commandedSpeedKmh, null);

  w.scheduler.tick(2.1);
  snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'IDLE');
  assert.equal(holder.commandedSpeedKmh, null);
  assert.equal(snap.last.outcome, 'HELD');
});

test('meet holds the holder and releases without a crossover', () => {
  const w = makeWorld({ meets: { crossoverChance: 1, minHoldSec: 0.5, maxHoldSec: 0.5 } });
  w.scheduler.tick(0.5);
  w.scheduler.tick(0.5);
  const holderId = w.scheduler.snapshot().active.holderId;
  let snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'HOLDING');
  assert.equal(snap.active.crossover, false);
  assert.equal(snap.active.routeId, null);
  assert.equal(snap.config.crossoverChance, 0);
  const holder = w.trains.find((t) => t.id === holderId);
  assert.equal(holder.commandedSpeedKmh, 0);

  w.scheduler.tick(0.6);
  snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'IDLE');
  assert.equal(snap.last.outcome, 'HELD');
  assert.equal(snap.last.crossed, false);
  assert.equal(holder.commandedSpeedKmh, null);
  assert.equal(w.routeCalls.length, 0);
});

test('a hold is not released while the block has an active hazard', () => {
  const w = makeWorld({ meets: { crossoverChance: 0, minHoldSec: 0.5, maxHoldSec: 0.5 }, hazardBlock: 'UP-B2' });
  w.scheduler.tick(0.5);
  w.scheduler.tick(0.5);
  w.scheduler.tick(2.0);
  let snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'HOLDING');
  const holder = w.trains.find((t) => t.id === snap.active.holderId);
  assert.equal(holder.commandedSpeedKmh, 0);

  w.__clearHazard();
  w.scheduler.tick(0.5);
  snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'IDLE');
  assert.equal(holder.commandedSpeedKmh, null);
});

test('releases the holder on timeout without requesting a route', () => {
  const w = makeWorld({ meets: { crossoverChance: 1, minHoldSec: 10, maxHoldSec: 10, holdTimeoutSec: 1.0 } });
  w.scheduler.tick(0.5);
  w.scheduler.tick(0.5);
  assert.equal(w.scheduler.snapshot().phase, 'HOLDING');
  w.scheduler.tick(1.1);
  const snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'IDLE');
  assert.equal(snap.last.outcome, 'HELD');
  assert.equal(w.routes.activeRoute(), null);
  assert.equal(w.routeCalls.length, 0);
});

test('same seed reproduces the same meet history; a different seed changes it', () => {
  const run = (seed) => {
    const w = makeWorld({
      meets: {
        seed,
        minGapSec: 0.2,
        maxGapSec: 0.2,
        minHoldSec: 0.5,
        maxHoldSec: 1.5,
        meetChance: 0.6,
        crossoverChance: 0.5,
        holdTimeoutSec: 5,
      },
    });
    for (let i = 0; i < 240; i++) {
      w.scheduler.tick(0.2);
      if (w.routes.activeRoute()) w.routes.clear();
    }
    return w.scheduler.snapshot().history;
  };
  assert.deepEqual(run(123), run(123));
  assert.notDeepEqual(run(123), run(124));
});

test('disabled meets never hold or grant routes', () => {
  const w = makeWorld({ meets: { enabled: false } });
  for (let i = 0; i < 20; i++) w.scheduler.tick(0.5);
  const snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'IDLE');
  assert.equal(snap.last, null);
  assert.equal(w.trains[0].commandedSpeedKmh, null);
  assert.equal(w.routeCalls.length, 0);
});

test('trigger starts the next meet at the next station window', () => {
  const w = makeWorld({ meets: { minGapSec: 999, maxGapSec: 999 } });
  w.scheduler.tick(0.5);
  assert.equal(w.scheduler.snapshot().phase, 'IDLE');
  assert.equal(w.scheduler.trigger(), true);
  w.scheduler.tick(0.5);
  assert.equal(w.scheduler.snapshot().phase, 'WAITING');
  w.scheduler.tick(0.5);
  assert.equal(w.scheduler.snapshot().phase, 'HOLDING');
});

import { config } from '../src/config.js';
import { makeState } from '../src/state.js';

test('state snapshot exposes live meet state and holds a train', () => {
  const cfg = {
    ...config,
    meets: {
      ...config.meets,
      enabled: true,
      seed: 7,
      minGapSec: 0.1,
      maxGapSec: 0.1,
      stationWaitSec: 120,
      minHoldSec: 1,
      maxHoldSec: 2,
      meetChance: 1,
      crossoverChance: 0.5,
    },
  };
  const state = makeState({ config: cfg });
  assert.ok(state.snapshot().meets, 'meets snapshot present');
  assert.equal(state.snapshot().meets.enabled, true);
  let meetObserved = false;
  for (let i = 0; i < 300; i++) {
    state.tick(0.5);
    const snap = state.snapshot();
    if (snap.meets.active || snap.meets.last) meetObserved = true;
    assert.notEqual(
      `${snap.trains[0].line}:${snap.trains[0].block}`,
      `${snap.trains[1].line}:${snap.trains[1].block}`,
      'no two trains in the same line and block',
    );
  }
  assert.ok(meetObserved, 'a meet occurred within 150 simulated seconds');
});

test('disabled meets leave the fixed-loop simulation unchanged', () => {
  const cfg = { ...config, meets: { ...config.meets, enabled: false } };
  const state = makeState({ config: cfg });
  for (let i = 0; i < 20; i++) state.tick(0.5);
  const snap = state.snapshot();
  assert.equal(snap.meets.enabled, false);
  assert.equal(snap.meets.phase, 'IDLE');
  assert.equal(snap.meets.last, null);
  assert.ok(snap.trains.some((t) => t.targetSpeedKmh > 0));
});
