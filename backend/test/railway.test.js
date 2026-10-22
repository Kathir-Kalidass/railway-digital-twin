import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildTopology, blockById, nextBlockId } from '../src/railway.js';

const config = { topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, zoneByIndex: ['zone1', 'zone2', 'zone2', 'zone2', 'zone1'], station: { id: 'station', name: 'Forest Halt', upIndex: 0, downIndex: 4, dwellSec: 20 }, crossovers: [{ id: 'X-A', from: 'UP-B0', fromOffsetM: 120, to: 'DOWN-B4', toOffsetM: 125.7699, atM: 120 }, { id: 'X-B', from: 'DOWN-B4', fromOffsetM: 5.7699, to: 'UP-B0', toOffsetM: 240, atM: 240 }] } };

test('builds both lines with ordered blocks and zone mapping', () => {
  const topo = buildTopology(config);
  assert.equal(topo.blocks.length, 10);
  assert.deepEqual(topo.lines[0].blocks, ['UP-B0', 'UP-B1', 'UP-B2', 'UP-B3', 'UP-B4']);
  assert.equal(blockById(topo, 'UP-B0').zone, 'zone1');
  assert.equal(blockById(topo, 'UP-B3').zone, 'zone2');
});

test('station maps to platform blocks', () => {
  const topo = buildTopology(config);
  assert.deepEqual(topo.station.blocks, { UP: 'UP-B0', DOWN: 'DOWN-B4' });
});

test('nextBlockId wraps the ring', () => {
  const topo = buildTopology(config);
  assert.equal(nextBlockId(topo, 'UP', 4), 'UP-B0');
  assert.equal(nextBlockId(topo, 'UP', 0), 'UP-B1');
});

test('per-line lengths are split evenly across blocks', () => {
  const topo = buildTopology({ topology: { ...config.topology, lineLengthM: { UP: 1253.9822, DOWN: 1228.8495 } } });
  assert.equal(blockById(topo, 'UP-B0').lengthM, 250.796);
  assert.equal(blockById(topo, 'DOWN-B4').lengthM, 245.77);
});

test('station crossover pair is built from config', () => {
  const topo = buildTopology({ topology: { ...config.topology, crossovers: [
    { id: 'X-A', from: 'UP-B0', fromOffsetM: 120, to: 'DOWN-B4', toOffsetM: 125.7699, atM: 120 },
    { id: 'X-B', from: 'DOWN-B4', fromOffsetM: 5.7699, to: 'UP-B0', toOffsetM: 240, atM: 240 },
  ] } });
  assert.deepEqual(topo.crossovers, [
    { id: 'X-A', from: 'UP-B0', fromOffsetM: 120, to: 'DOWN-B4', toOffsetM: 125.7699, atM: 120 },
    { id: 'X-B', from: 'DOWN-B4', fromOffsetM: 5.7699, to: 'UP-B0', toOffsetM: 240, atM: 240 },
  ]);
});

test('station blocks expose stadium lengths', () => {
  const topo = buildTopology({ topology: { ...config.topology, lineLengthM: { UP: 1253.9822, DOWN: 1228.8495 } } });
  assert.deepEqual(topo.station.blocks, { UP: 'UP-B0', DOWN: 'DOWN-B4' });
  assert.equal(topo.crossovers[0].fromOffsetM, 120);
  assert.equal(topo.crossovers[1].atM, 240);
});
