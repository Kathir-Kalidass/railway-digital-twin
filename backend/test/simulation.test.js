import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildTopology } from '../src/railway.js';
import { deriveBlockAspects } from '../src/signalling.js';
import { occupyBlocks, stepTrains } from '../src/simulation.js';

const config = { topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'x', upIndex: 2, downIndex: 2, dwellSec: 20 } } };
const sim = { lookaheadBlocks: 2, cautionSpeedKmh: 30, brakeMps2: 2.0, accelMps2: 0.6, defaultTargetSpeedKmh: 48 };
const zones = () => ({ zone1: { targetSpeedKmh: 48, wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' }, zone2: { targetSpeedKmh: 48, wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' } });
const train = (o = {}) => ({ id: 'T1', line: 'UP', direction: 'UP', block: 'UP-B0', offsetM: 0, speedKmh: 0, targetSpeedKmh: 48, lengthM: 60, status: 'RUNNING', zone: 'zone1', ...o });

test('occupyBlocks marks every block overlapped by the consist', () => {
  const topo = buildTopology(config);
  occupyBlocks(topo, [train({ offsetM: 280, lengthM: 60 })]); // 20m left in B0, 40m into B1
  assert.equal(topo.blocks.find((b) => b.id === 'UP-B0').occupiedBy, 'T1');
  assert.equal(topo.blocks.find((b) => b.id === 'UP-B1').occupiedBy, 'T1');
  assert.equal(topo.blocks.find((b) => b.id === 'UP-B2').occupiedBy, null);
});

test('accelerates toward target and advances position', () => {
  const topo = buildTopology(config);
  const t = train();
  stepTrains({ topology: topo, simulation: sim, zones: zones(), trains: [t], dtSec: 1 });
  assert.ok(t.speedKmh > 0);
  assert.ok(t.offsetM > 0);
});

test('unoccupied block folds into the next block on wrap-free travel', () => {
  const topo = buildTopology(config);
  const t = train({ offsetM: 299, speedKmh: 80 });
  stepTrains({ topology: topo, simulation: sim, zones: zones(), trains: [t], dtSec: 1 });
  assert.equal(t.block, 'UP-B1');
  assert.ok(t.offsetM >= 0 && t.offsetM < 300);
});

test('RED aspect ahead holds the train', () => {
  const topo = buildTopology(config);
  const t = train({ block: 'UP-B0', offsetM: 0, speedKmh: 40 });
  const blocks = topo.blocks.map((b) => ({ ...b }));
  blocks.find((b) => b.id === 'UP-B1').occupiedBy = 'T2';
  const aspects = deriveBlockAspects({ topology: topo, blocks, zones: zones(), lookaheadBlocks: 2 });
  stepTrains({ topology: topo, simulation: sim, zones: zones(), trains: [t], dtSec: 1, aspects });
  assert.ok(t.targetSpeedKmh < 40);
});

test('deterministic for a fixed number of equal steps', () => {
  const run = () => {
    const topo = buildTopology(config);
    const t = train();
    for (let i = 0; i < 20; i++) stepTrains({ topology: topo, simulation: sim, zones: zones(), trains: [t], dtSec: 0.5 });
    return t;
  };
  const a = run(); const b = run();
  assert.equal(a.offsetM, b.offsetM);
  assert.equal(a.speedKmh, b.speedKmh);
});
