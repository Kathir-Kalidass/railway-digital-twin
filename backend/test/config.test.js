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
  assert.equal(config.topology.lineLengthM.UP, 753.9822);
  assert.equal(config.topology.lineLengthM.DOWN, 728.8495);
  assert.deepEqual(config.topology.crossovers, [
    { id: 'X-UP-DOWN', from: 'UP-B2', to: 'DOWN-B2' },
    { id: 'X-DOWN-UP', from: 'DOWN-B2', to: 'UP-B2' },
  ]);
});

test('config exposes meet scheduler defaults', () => {
  assert.equal(typeof config.meets, 'object');
  assert.equal(config.meets.enabled, true);
  assert.equal(config.meets.seed, 20261022);
  assert.ok(config.meets.minGapSec <= config.meets.maxGapSec);
  assert.ok(config.meets.meetChance >= 0 && config.meets.meetChance <= 1);
  assert.ok(config.meets.crossoverChance >= 0 && config.meets.crossoverChance <= 1);
});
