import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildTopology } from '../src/railway.js';
import { deriveBlockAspects, zoneSignal, mostRestrictive, isZoneRestrictive } from '../src/signalling.js';

const config = { topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'x', upIndex: 2, downIndex: 2, dwellSec: 20 } } };
const zones = () => ({ zone1: { wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' }, zone2: { wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' } });

test('mostRestrictive orders GREEN < YELLOW < RED', () => {
  assert.equal(mostRestrictive('GREEN', 'YELLOW'), 'YELLOW');
  assert.equal(mostRestrictive('YELLOW', 'RED'), 'RED');
  assert.equal(mostRestrictive('GREEN', 'GREEN'), 'GREEN');
});

test('clear line yields all GREEN', () => {
  const topo = buildTopology(config);
  const a = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones: zones(), lookaheadBlocks: 2 });
  assert.ok(Object.values(a).every((v) => v === 'GREEN'));
});

test('occupancy: occupied block RED, block behind YELLOW', () => {
  const topo = buildTopology(config);
  const blocks = topo.blocks.map((b) => ({ ...b }));
  blocks.find((b) => b.id === 'UP-B3').occupiedBy = 'T1';
  const a = deriveBlockAspects({ topology: topo, blocks, zones: zones(), lookaheadBlocks: 2 });
  assert.equal(a['UP-B3'], 'RED');
  assert.equal(a['UP-B2'], 'YELLOW');
  assert.equal(a['UP-B0'], 'GREEN');
});

test('zone hazard forces every block in the zone RED', () => {
  const topo = buildTopology(config);
  const z = zones(); z.zone1.wildlifeDetected = true;
  const a = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones: z, lookaheadBlocks: 2 });
  assert.equal(a['UP-B0'], 'RED');
  assert.equal(a['UP-B1'], 'RED');
  assert.equal(a['UP-B3'], 'GREEN');
});

test('zoneSignal reflects hazard layer and cross-zone caution', () => {
  const z = zones();
  assert.equal(zoneSignal('zone1', z), 'GREEN');
  assert.equal(zoneSignal('zone2', z), 'GREEN');
  z.zone1.wildlifeDetected = true;
  assert.equal(zoneSignal('zone1', z), 'RED');
  assert.equal(zoneSignal('zone2', z), 'YELLOW');
  z.zone2.sensorHealthy = false;
  assert.equal(zoneSignal('zone2', z), 'RED');
});

test('staged hazards show caution then stop aspects', () => {
  const topo = buildTopology(config);
  const blocks = topo.blocks.map((b) => ({ ...b, occupiedBy: null }));
  const z = zones();
  const suspected = {
    'UP-B1': { blockId: 'UP-B1', line: 'UP', zone: 'zone1', stage: 'SUSPECTED', active: true, sensorSources: ['trackside'] },
  };
  let aspects = deriveBlockAspects({ topology: topo, blocks, zones: z, blockHazards: suspected, lookaheadBlocks: 2 });
  assert.equal(aspects['UP-B1'], 'YELLOW');
  assert.equal(aspects['UP-B0'], 'YELLOW');
  assert.equal(zoneSignal('zone1', z, suspected), 'YELLOW');

  const confirmed = {
    'UP-B1': { blockId: 'UP-B1', line: 'UP', zone: 'zone1', stage: 'CONFIRMED', active: true, sensorSources: ['trackside'] },
  };
  aspects = deriveBlockAspects({ topology: topo, blocks, zones: z, blockHazards: confirmed, lookaheadBlocks: 2 });
  assert.equal(aspects['UP-B1'], 'RED');
  assert.equal(aspects['UP-B0'], 'YELLOW');
  assert.equal(zoneSignal('zone1', z, confirmed), 'RED');
});

test('isZoneRestrictive covers wildlife, fault, recovery', () => {
  assert.equal(isZoneRestrictive({ wildlifeDetected: true, sensorHealthy: true, status: 'NORMAL' }), true);
  assert.equal(isZoneRestrictive({ wildlifeDetected: false, sensorHealthy: false, status: 'NORMAL' }), true);
  assert.equal(isZoneRestrictive({ wildlifeDetected: false, sensorHealthy: true, status: 'RECOVERY_REQUIRED' }), true);
  assert.equal(isZoneRestrictive({ wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' }), false);
});
