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

function envelope(payload, overrides = {}) {
  return {
    request_id: 'esp32-boot-1-1', zone: 'zone1', event: 'DEVICE_TELEMETRY',
    timestamp: new Date().toISOString(), clockValid: true, source: 'esp32',
    payload: { device: 'esp32', sensorHealthy: true, wildlifeDetected: false, uptimeMs: 10, ...payload },
    ...overrides,
  };
}

test('esp32 envelope sets sensor through the narrow setter', () => {
  const { state, ingest } = setup();
  ingest.handle('railway/telemetry/esp32', envelope({ sensorHealthy: false }));
  assert.equal(state.snapshot().zones.zone1.sensorHealthy, false);
});

test('esp32 near-animal telemetry is stored informationally', () => {
  const { state, ingest } = setup();
  ingest.handle('railway/telemetry/esp32', envelope({ nearAnimal: true }));
  assert.equal(state.snapshot().zones.zone1.esp32NearAnimal, true);
});

test('esp32 out-of-zone and clock-invalid envelopes are rejected without mutation', () => {
  const { state, ingest } = setup();
  const initial = state.snapshot();
  ingest.handle('railway/telemetry/esp32', envelope({ sensorHealthy: false }, { zone: 'zone2' }));
  assert.equal(state.snapshot().lastEvent, 'INVALID_TELEMETRY');
  assert.equal(state.snapshot().zones.zone1.sensorHealthy, initial.zones.zone1.sensorHealthy);
  ingest.handle('railway/telemetry/esp32', envelope({ sensorHealthy: false }, {
    request_id: 'esp32-boot-1-2', timestamp: null, clockValid: false,
  }));
  assert.equal(state.snapshot().lastEvent, 'INVALID_TELEMETRY');
});

test('esp32 telemetry never mutates train state and rejects replay', () => {
  const { state, ingest } = setup();
  const before = JSON.stringify(state.snapshot().train);
  const message = envelope({ sensorHealthy: false });
  ingest.handle('railway/telemetry/esp32', message);
  assert.equal(JSON.stringify(state.snapshot().train), before);
  ingest.handle('railway/telemetry/esp32', message);
  assert.equal(state.snapshot().lastEvent, 'INVALID_TELEMETRY');
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
