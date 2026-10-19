import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildTopology, blockById, nextBlockId } from '../src/railway.js';

const config = { topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'Forest Halt', upIndex: 2, downIndex: 2, dwellSec: 20 } } };

test('builds both lines with ordered blocks and zone mapping', () => {
  const topo = buildTopology(config);
  assert.equal(topo.blocks.length, 10);
  assert.deepEqual(topo.lines[0].blocks, ['UP-B0', 'UP-B1', 'UP-B2', 'UP-B3', 'UP-B4']);
  assert.equal(blockById(topo, 'UP-B0').zone, 'zone1');
  assert.equal(blockById(topo, 'UP-B3').zone, 'zone2');
});

test('station maps to platform blocks', () => {
  const topo = buildTopology(config);
  assert.deepEqual(topo.station.blocks, { UP: 'UP-B2', DOWN: 'DOWN-B2' });
});

test('nextBlockId wraps the ring', () => {
  const topo = buildTopology(config);
  assert.equal(nextBlockId(topo, 'UP', 4), 'UP-B0');
  assert.equal(nextBlockId(topo, 'UP', 0), 'UP-B1');
});
