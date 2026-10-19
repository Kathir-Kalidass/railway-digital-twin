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
  assert.equal(config.trains.length, 4);
  assert.equal(config.topology.lines.length, 2);
  assert.ok(config.simulation.tickMs > 0);
});
