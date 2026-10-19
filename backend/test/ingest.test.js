import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeState } from '../src/state.js';
import { makeEvents } from '../src/events.js';
import { makeBus } from '../src/bus.js';
import { makeIngest } from '../src/ingest.js';

function fakeMqtt() { return { published: [], publish(t, o, opts = {}) { this.published.push({ t, o, opts }); }, subscribe() {}, isConnected: () => true }; }

function setup() {
  const mqtt = fakeMqtt();
  const state = makeState({ config: { zones: ['zone1', 'zone2'] } });
  const bus = makeBus({ mqtt, state, events: makeEvents() });
  const ingest = makeIngest({ state, bus, config: { zones: ['zone1', 'zone2'] } });
  return { mqtt, state, ingest };
}

test('zone train telemetry updates occupancy and republishes state', () => {
  const { mqtt, state, ingest } = setup();
  state.setBrokerConnected(true);
  ingest.handle('railway/zone1/train', { trainPresent: true, speedKmh: 20 });
  assert.equal(state.snapshot().zones.zone1.trainPresent, true);
  assert.ok(mqtt.published.some((m) => m.t === 'railway/state'));
});

test('esp32 telemetry marks device and forces fault when unhealthy', () => {
  const { state, ingest, mqtt } = setup();
  state.setBrokerConnected(true);
  ingest.handle('railway/telemetry/esp32', { device: 'esp32', sensorHealthy: false });
  assert.equal(state.snapshot().overall, 'SENSOR_FAULT');
  assert.ok(mqtt.published.some((m) => m.t === 'railway/security/events' || m.t === 'railway/alerts' || m.t === 'railway/state'));
});

test('disconnect sets COMM_LOST and reconnect reconciles', () => {
  const { state, ingest, mqtt } = setup();
  ingest.onBrokerConnected(true);
  assert.equal(state.snapshot().overall, 'NORMAL');
  ingest.onBrokerConnected(false);
  assert.equal(state.snapshot().overall, 'COMM_LOST');
  ingest.onBrokerConnected(true);
  assert.equal(state.snapshot().overall, 'NORMAL');
  assert.ok(mqtt.published.filter((m) => m.t === 'railway/state').length >= 2);
});
