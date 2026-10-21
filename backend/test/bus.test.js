import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeState } from '../src/state.js';
import { makeEvents } from '../src/events.js';
import { makeBus } from '../src/bus.js';

function fakeMqtt() {
  return { out: [], published: [], publish(t, o, opts = {}) { this.published.push({ t, o, opts }); }, isConnected: () => true };
}

test('snapshot publishes retained state and per-zone signals', () => {
  const mqtt = fakeMqtt();
  const state = makeState({ config: { zones: ['zone1', 'zone2'] } });
  const bus = makeBus({ mqtt, state, events: makeEvents() });
  bus.snapshot();
  const stateMsg = mqtt.published.find((m) => m.t === 'railway/state');
  assert.equal(stateMsg.opts.retain, true);
  assert.ok(mqtt.published.find((m) => m.t === 'railway/zone1/signal'));
  assert.ok(mqtt.published.find((m) => m.t === 'railway/zone2/signal'));
});

test('snapshot publishes retained per-block signals', () => {
  const mqtt = fakeMqtt();
  const state = { snapshot: () => ({ zones: { zone1: { signal: 'GREEN' } }, blocks: [{ id: 'UP-B0', line: 'UP', zone: 'zone1', occupiedBy: 'T1', signal: 'RED' }], updatedAt: 'X' }) };
  const bus = makeBus({ mqtt, state, events: makeEvents() });
  bus.snapshot();
  const blockMsg = mqtt.published.find((m) => m.t === 'railway/signal/UP-B0');
  assert.ok(blockMsg);
  assert.equal(blockMsg.opts.retain, true);
  assert.equal(blockMsg.o.signal, 'RED');
  assert.equal(blockMsg.o.occupiedBy, 'T1');
});

test('events are recorded and published newest-first', () => {
  const mqtt = fakeMqtt();
  const events = makeEvents();
  const bus = makeBus({ mqtt, state: makeState({ config: { zones: ['zone1', 'zone2'] } }), events });
  bus.event({ type: 'A' });
  bus.event({ type: 'B' });
  assert.equal(mqtt.published.filter((m) => m.t === 'railway/events').length, 2);
  const listed = events.list();
  assert.equal(listed.length, 2);
  assert.equal(listed[0].type, 'B');
});
