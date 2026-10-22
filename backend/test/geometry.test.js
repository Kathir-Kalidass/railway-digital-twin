import { test } from 'node:test';
import assert from 'node:assert/strict';
import { config } from '../src/config.js';
import { buildTopology, blockById } from '../src/railway.js';
import {
  blockOffsetToPhysical,
  operationalToPhysical,
  physicalToOperational,
  physicalToBlockOffset,
} from '../src/geometry.js';

test('line lengths and block offsets map in both directions', () => {
  const topo = buildTopology(config);
  assert.ok(Math.abs(topo.lines.find((l) => l.id === 'UP').lengthM - 1253.9822) < 0.001);
  assert.ok(Math.abs(topo.lines.find((l) => l.id === 'DOWN').lengthM - 1228.8495) < 0.001);

  assert.ok(Math.abs(operationalToPhysical(topo, 'UP', 120) - 120) < 0.001);
  assert.ok(Math.abs(operationalToPhysical(topo, 'DOWN', 988.8495) - 240) < 0.001);
  assert.ok(Math.abs(physicalToOperational(topo, 'DOWN', 240) - 988.8495) < 0.01);

  assert.ok(Math.abs(blockOffsetToPhysical(topo, 'UP', 'UP-B0', 120) - 120) < 0.001);
  assert.ok(Math.abs(blockOffsetToPhysical(topo, 'DOWN', 'DOWN-B4', 5.7699) - 240) < 0.01);

  const at = physicalToBlockOffset(topo, 'DOWN', 240);
  assert.equal(at.blockId, 'DOWN-B4');
  assert.ok(Math.abs(at.offsetM - 5.7699) < 0.01);
  assert.ok(Math.abs(physicalToOperational(topo, 'DOWN', operationalToPhysical(topo, 'DOWN', 0)) - 0) < 0.001);
});

test('station blocks and zone map are the stadium layout', () => {
  const topo = buildTopology(config);
  assert.equal(topo.station.blocks.UP, 'UP-B0');
  assert.equal(topo.station.blocks.DOWN, 'DOWN-B4');
  assert.deepEqual(config.topology.zoneByIndex, ['zone1', 'zone2', 'zone2', 'zone2', 'zone1']);
  assert.equal(blockById(topo, 'UP-B0').zone, 'zone1');
  assert.equal(blockById(topo, 'DOWN-B4').zone, 'zone1');
});
