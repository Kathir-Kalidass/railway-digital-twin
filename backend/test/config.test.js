import { test } from 'node:test';
import assert from 'node:assert/strict';

test('config exposes required defaults', async () => {
  const { config } = await import('../src/config.js');
  assert.deepEqual(config.zones, ['zone1', 'zone2']);
  assert.equal(config.port, 3001);
  assert.equal(config.mqttUser, 'backend');
  assert.ok(config.bcryptRounds >= 12);
  assert.equal(config.seedUsers.length, 3);
  assert.deepEqual(config.seedUsers.map((u) => u.role).sort(), ['admin', 'operator', 'viewer']);
});
