import { test } from 'node:test';
import assert from 'node:assert/strict';
import { config } from '../src/config.js';

test('config exposes required defaults', async () => {
  const { config } = await import('../src/config.js');
  assert.deepEqual(config.zones, ['zone1', 'zone2']);
  assert.equal(config.port, 3001);
  assert.equal(config.mqttUser, 'backend');
  assert.ok(config.bcryptRounds >= 12);
  assert.equal(config.seedUsers.length, 3);
  assert.deepEqual(config.seedUsers.map((u) => u.role).sort(), ['admin', 'operator', 'viewer']);
});

test('config exposes topology, trains and simulation settings', () => {
  assert.equal(config.zones.length, 2);
  assert.deepEqual(config.trains.map((t) => t.id), ['T1', 'T3']);
  assert.equal(config.topology.lines.length, 2);
  assert.ok(config.simulation.tickMs > 0);
});

test('config exposes per-line lengths and the station crossover pair', () => {
  assert.equal(config.topology.lineLengthM.UP, 1253.9822);
  assert.equal(config.topology.lineLengthM.DOWN, 1228.8495);
  assert.equal(config.topology.station.upIndex, 0);
  assert.equal(config.topology.station.downIndex, 4);
  assert.deepEqual(config.topology.crossovers.map((c) => c.id), ['X-A', 'X-B']);
  assert.equal(config.meets.crossoverChance, 0);
});

test('config exposes meet scheduler defaults', () => {
  assert.equal(typeof config.meets, 'object');
  assert.equal(config.meets.enabled, true);
  assert.equal(config.meets.seed, 20261022);
  assert.ok(config.meets.minGapSec <= config.meets.maxGapSec);
  assert.ok(config.meets.meetChance >= 0 && config.meets.meetChance <= 1);
  assert.ok(config.meets.crossoverChance >= 0 && config.meets.crossoverChance <= 1);
});

test('config exposes near-animal warning defaults', () => {
  assert.equal(config.nearAnimal.enabled, true);
  assert.equal(config.nearAnimal.serviceSpeedKmh, 30);
  assert.ok(config.nearAnimal.confirmFrames >= 2);
  assert.equal(config.nearAnimal.leadFactor, 1.25);
});

test('config exposes wrong-line interlock defaults', () => {
  assert.equal(config.wrongLine.enabled, true);
  assert.equal(config.wrongLine.speedKmh, 30);
  assert.ok(config.wrongLine.approachMaxM > config.wrongLine.approachMinM);
  assert.equal(config.wrongLine.holdBeforeEntryM, 80);
});
