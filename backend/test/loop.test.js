import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeState } from '../src/state.js';
import { makeEvents } from '../src/events.js';
import { makeBus } from '../src/bus.js';
import { buildTopology } from '../src/railway.js';
import { makeLoop } from '../src/loop.js';

const config = {
  zones: ['zone1', 'zone2'],
  topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, lineLengthM: { UP: 753.9822, DOWN: 728.8495 }, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'x', upIndex: 2, downIndex: 2, dwellSec: 20 }, crossovers: [] },
  trains: [{ id: 'T1', line: 'UP', direction: 'UP', startBlock: 0, startOffsetM: 0, lengthM: 60 }],
  simulation: { tickMs: 500, lookaheadBlocks: 2, cautionSpeedKmh: 30, brakeMps2: 2.0, accelMps2: 0.6, defaultTargetSpeedKmh: 48 },
};

function fakeMqtt() {
  return { published: [], publish(t, o, opts = {}) { this.published.push({ t, o, opts }); }, subscribe() {}, isConnected: () => true };
}

test('loop step ticks state and publishes a snapshot', () => {
  const mqtt = fakeMqtt();
  const state = makeState({ config, topology: buildTopology(config) });
  const bus = makeBus({ mqtt, state, events: makeEvents() });
  const loop = makeLoop({ state, bus, config, intervalMs: 500 });
  state.setBrokerConnected(true);
  const before = state.snapshot().trains[0].offsetM;
  loop.step();
  loop.step();
  assert.ok(state.snapshot().trains[0].offsetM > before);
  assert.equal(mqtt.published.filter((m) => m.t === 'railway/state').length, 2);
  assert.equal(loop.isRunning(), false);
});

test('loop start and stop are idempotent', () => {
  const mqtt = fakeMqtt();
  const state = makeState({ config, topology: buildTopology(config) });
  const bus = makeBus({ mqtt, state, events: makeEvents() });
  const loop = makeLoop({ state, bus, config, intervalMs: 500 });
  loop.start();
  loop.start();
  assert.equal(loop.isRunning(), true);
  loop.stop();
  loop.stop();
  assert.equal(loop.isRunning(), false);
});
