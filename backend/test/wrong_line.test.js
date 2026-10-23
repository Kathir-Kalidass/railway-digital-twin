import { test } from 'node:test';
import assert from 'node:assert/strict';
import { config } from '../src/config.js';
import { buildTopology, blockById } from '../src/railway.js';
import { physicalToBlockOffset } from '../src/geometry.js';
import { makeWrongLine } from '../src/wrong_line.js';

function world({ hazard = false, meet = false, onRestore = null } = {}) {
  const topology = buildTopology(config);
  const zones = Object.fromEntries(config.zones.map((id) => [id, {
    id, targetSpeedKmh: 48, wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL',
  }]));
  const trains = [
    { id: 'T1', line: 'UP', block: 'UP-B0', offsetM: 40, speedKmh: 48, targetSpeedKmh: 48, commandedSpeedKmh: null, lengthM: 60, travelSign: 1, zone: 'zone1' },
    { id: 'T3', line: 'DOWN', block: 'DOWN-B2', offsetM: 0, speedKmh: 45, targetSpeedKmh: 45, commandedSpeedKmh: null, lengthM: 60, travelSign: -1, zone: 'zone2' },
  ];
  const wl = makeWrongLine({
    topology, trains, zones, config,
    hasActiveHazard: (id) => hazard && (id === 'UP-B0' || id === 'DOWN-B4'),
    isMeetActive: () => meet,
    onRestore,
  });
  return { topology, trains, zones, wl };
}

test('eligibility reports approach distance and section state', () => {
  const { wl } = world();
  const e = wl.snapshot().eligibility;
  assert.equal(e.T1.eligible, true);
  assert.ok(Math.abs(e.T1.distanceToEntryM - 80) < 0.1);
  assert.equal(e.T3.eligible, false);
  assert.equal(e.T3.reason, 'approach');

  const blocked = world({ meet: true }).wl.snapshot().eligibility;
  assert.equal(blocked.T1.reason, 'meet_active');

  const hazard = world({ hazard: true }).wl.snapshot().eligibility;
  assert.equal(hazard.T1.reason, 'hazard');
});

test('T1 completes APPROACH -> CROSS_ENTRY -> WRONG_LINE -> CROSS_EXIT -> CLEARANCE -> DONE', () => {
  const { trains, wl } = world();
  const t1 = trains[0];
  const t3 = trains[1];
  const granted = wl.request({ trainId: 'T1' });
  assert.equal(granted.ok, true);
  assert.equal(wl.snapshot().active.phase, 'APPROACH');
  assert.ok(t3.commandedSpeedKmh > 0, 'opponent runs toward its hold point');
  assert.equal(blockById(wl.topology, 'UP-B0').reservedBy.startsWith('WL-'), true);

  t1.block = 'UP-B0';
  t1.offsetM = 120;
  wl.tick(0.5);
  assert.equal(wl.snapshot().active.phase, 'CROSS_ENTRY');
  assert.equal(t1.line, 'DOWN');
  assert.equal(t1.operationalSign, -1);

  for (let i = 0; i < 80 && wl.snapshot().active; i++) wl.tick(0.5);
  const snap = wl.snapshot();
  assert.equal(snap.active, null);
  assert.equal(snap.lastEvent, 'WRONG_LINE_COMPLETED');
  assert.equal(t1.line, 'UP');
  assert.equal(t1.operationalSign, 1);
  assert.equal(t3.commandedSpeedKmh, 48);
  assert.equal(blockById(wl.topology, 'UP-B0').reservedBy, null);
  assert.equal(blockById(wl.topology, 'DOWN-B4').reservedBy, null);
});

test('opponent holds at the configured point instead of stopping in place', () => {
  const { topology, trains, wl } = world();
  const t3 = trains[1];
  assert.equal(wl.request({ trainId: 'T1' }).ok, true);
  assert.ok(t3.commandedSpeedKmh > 0, 'far opponent keeps moving toward the hold point');

  const far = physicalToBlockOffset(topology, 'DOWN', 400);
  t3.line = 'DOWN';
  t3.block = far.blockId;
  t3.offsetM = far.offsetM;
  t3.physicalM = 400;
  wl.tick(0.5);
  assert.ok(t3.commandedSpeedKmh > 0, 'opponent outside braking distance keeps moving');

  const near = physicalToBlockOffset(topology, 'DOWN', 350);
  t3.block = near.blockId;
  t3.offsetM = near.offsetM;
  t3.physicalM = 350;
  wl.tick(0.5);
  assert.equal(t3.commandedSpeedKmh, 0, 'opponent stops at the hold point');
});

test('cancel is allowed only during APPROACH', () => {
  const { trains, wl } = world();
  assert.equal(wl.request({ trainId: 'T1' }).ok, true);
  assert.equal(wl.cancel({ trainId: 'T1' }).ok, true);
  assert.equal(wl.snapshot().active, null);
  assert.equal(trains[1].commandedSpeedKmh, 48);
});

test('hazard aborts and releases after the section clears', () => {
  let hazard = false;
  const topology = buildTopology(config);
  const zones = Object.fromEntries(config.zones.map((id) => [id, { id, targetSpeedKmh: 48, wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' }]));
  const trains = [
    { id: 'T1', line: 'UP', block: 'UP-B0', offsetM: 40, speedKmh: 30, targetSpeedKmh: 30, commandedSpeedKmh: null, lengthM: 60, travelSign: 1, zone: 'zone1' },
    { id: 'T3', line: 'DOWN', block: 'DOWN-B2', offsetM: 0, speedKmh: 45, targetSpeedKmh: 45, commandedSpeedKmh: null, lengthM: 60, travelSign: -1, zone: 'zone2' },
  ];
  const wl = makeWrongLine({ topology, trains, zones, config, hasActiveHazard: () => hazard, isMeetActive: () => false });
  assert.equal(wl.request({ trainId: 'T1' }).ok, true);
  wl.tick(0.5);
  hazard = true;
  wl.tick(0.5);
  assert.equal(wl.snapshot().active.phase, 'ABORTED_BLOCKED');
  hazard = false;
  wl.tick(0.5);
  assert.equal(wl.snapshot().active, null);
  assert.equal(wl.snapshot().lastEvent, 'WRONG_LINE_ABORTED');
});

test('completion restores fallback 48 and logs when saved speeds are missing', () => {
  const restores = [];
  const { trains, wl } = world({ onRestore: (e) => restores.push(e) });
  const t1 = trains[0];
  const t3 = trains[1];
  assert.equal(wl.request({ trainId: 'T1' }).ok, true);
  t1.block = 'UP-B0';
  t1.offsetM = 120;
  wl.tick(0.5);
  for (let i = 0; i < 80 && wl.snapshot().active; i++) wl.tick(0.5);
  assert.equal(wl.snapshot().lastEvent, 'WRONG_LINE_COMPLETED');
  assert.equal(t1.commandedSpeedKmh, 48);
  assert.equal(t3.commandedSpeedKmh, 48);
  assert.equal(restores.length, 2);
  assert.equal(restores[0].reason, 'WRONG_LINE_ROUTE_TRAIN');
  assert.equal(restores[0].trainId, 'T1');
  assert.equal(restores[1].reason, 'WRONG_LINE_COMPLETED');
  assert.equal(restores[1].trainId, 'T3');
});

test('cancel restores fallback 48 for the opponent when its saved speed is missing', () => {
  const restores = [];
  const { trains, wl } = world({ onRestore: (e) => restores.push(e) });
  assert.equal(wl.request({ trainId: 'T1' }).ok, true);
  assert.equal(wl.cancel({ trainId: 'T1' }).ok, true);
  assert.equal(wl.snapshot().active, null);
  assert.equal(trains[1].commandedSpeedKmh, 48);
  assert.equal(restores.length, 2);
  assert.equal(restores[1].reason, 'WRONG_LINE_CANCELLED');
});
