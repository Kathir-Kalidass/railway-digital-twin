import { test } from 'node:test';
import assert from 'node:assert/strict';
import { connectAs, waitFor } from './helpers/broker.js';

test('dashboard cannot publish a command (ACL denies)', async () => {
  const observer = connectAs('godot'); // godot may read railway/commands/zone1
  await waitFor(() => observer.connected);
  await new Promise((r) => observer.subscribe('railway/commands/zone1', r));
  const seen = [];
  observer.on('message', (t) => seen.push(t));
  const dash = connectAs('dashboard');
  await waitFor(() => dash.connected);
  dash.publish('railway/commands/zone1', JSON.stringify({ evil: true }));
  await new Promise((r) => setTimeout(r, 500));
  assert.equal(seen.length, 0);
  dash.end(true); observer.end(true);
});

test('godot can read authoritative state and per-block signals', async () => {
  const godot = connectAs('godot');
  await waitFor(() => godot.connected);
  await Promise.all([
    new Promise((r) => godot.subscribe('railway/state', r)),
    new Promise((r) => godot.subscribe('railway/signal/UP-B0', r)),
  ]);
  const seen = [];
  godot.on('message', (topic, payload) => seen.push([topic, payload.toString()]));

  const backend = connectAs('backend');
  await waitFor(() => backend.connected);
  backend.publish('railway/state', JSON.stringify({ marker: 'godot-state-read' }));
  backend.publish('railway/signal/UP-B0', JSON.stringify({ marker: 'godot-block-read' }));
  await waitFor(() => seen.some(([, body]) => body.includes('godot-state-read')) && seen.some(([, body]) => body.includes('godot-block-read')));
  assert.ok(seen.some(([topic, body]) => topic === 'railway/state' && body.includes('godot-state-read')));
  assert.ok(seen.some(([topic, body]) => topic === 'railway/signal/UP-B0' && body.includes('godot-block-read')));

  godot.end(true); backend.end(true);
});

test('godot cannot publish retired zone train telemetry', async () => {
  const observer = connectAs('backend'); // backend may still read the retired topic
  await waitFor(() => observer.connected);
  await new Promise((r) => observer.subscribe('railway/zone1/train', r));
  const seen = [];
  observer.on('message', (topic, payload) => seen.push(payload.toString()));
  const godot = connectAs('godot');
  await waitFor(() => godot.connected);
  godot.publish('railway/zone1/train', JSON.stringify({ marker: 'retired-train-write' }));
  await new Promise((r) => setTimeout(r, 400));
  assert.equal(seen.length, 0);
  godot.end(true); observer.end(true);
});

test('esp32 cannot read per-block signals', async () => {
  const esp32 = connectAs('esp32');
  await waitFor(() => esp32.connected);
  await new Promise((r) => esp32.subscribe('railway/signal/UP-B0', r));
  const seen = [];
  esp32.on('message', (topic, payload) => seen.push(payload.toString()));
  const backend = connectAs('backend');
  await waitFor(() => backend.connected);
  backend.publish('railway/signal/UP-B0', JSON.stringify({ marker: 'esp32-signal-denied' }));
  await new Promise((r) => setTimeout(r, 400));
  assert.equal(seen.length, 0);
  esp32.end(true); backend.end(true);
});

test('godot cannot publish aggregate state', async () => {
  const observer = connectAs('dashboard'); // dashboard may read railway/state
  await waitFor(() => observer.connected);
  await new Promise((r) => observer.subscribe('railway/state', r));
  const seen = [];
  observer.on('message', (t, m) => {
    try {
      if (JSON.parse(m.toString()).hacked) seen.push(t);
    } catch {
      seen.push(t);
    }
  });
  const godot = connectAs('godot');
  await waitFor(() => godot.connected);
  godot.publish('railway/state', JSON.stringify({ hacked: true }));
  await new Promise((r) => setTimeout(r, 500));
  assert.equal(seen.length, 0);
  godot.end(true); observer.end(true);
});

test('esp32 can publish only its telemetry and read only its command topic', async () => {
  const telemetryObserver = connectAs('backend');
  await waitFor(() => telemetryObserver.connected);
  await new Promise((resolve) => telemetryObserver.subscribe('railway/telemetry/esp32', resolve));
  const receivedTelemetry = [];
  telemetryObserver.on('message', (topic, payload) => receivedTelemetry.push([topic, payload.toString()]));

  const esp32 = connectAs('esp32');
  await waitFor(() => esp32.connected);
  esp32.publish('railway/telemetry/esp32', JSON.stringify({ device: 'esp32', sensorHealthy: true }));
  await waitFor(() => receivedTelemetry.some(([topic]) => topic === 'railway/telemetry/esp32'));

  await new Promise((resolve) => esp32.subscribe('railway/commands/esp32', resolve));
  const receivedCommands = [];
  esp32.on('message', (topic, payload) => receivedCommands.push([topic, payload.toString()]));
  const backend = connectAs('backend');
  await waitFor(() => backend.connected);
  backend.publish('railway/commands/esp32', JSON.stringify({ request_id: 'acl-ok', zone: 'zone1' }));
  await waitFor(() => receivedCommands.some(([topic]) => topic === 'railway/commands/esp32'));

  esp32.end(true); backend.end(true); telemetryObserver.end(true);
});

test('esp32 cannot publish command, state, or signal topics', async () => {
  const commandObserver = connectAs('esp32');
  const stateObserver = connectAs('dashboard');
  const signalObserver = connectAs('godot');
  await Promise.all([waitFor(() => commandObserver.connected), waitFor(() => stateObserver.connected), waitFor(() => signalObserver.connected)]);
  await Promise.all([
    new Promise((resolve) => commandObserver.subscribe('railway/commands/esp32', resolve)),
    new Promise((resolve) => stateObserver.subscribe('railway/state', resolve)),
    new Promise((resolve) => signalObserver.subscribe('railway/zone1/signal', resolve)),
  ]);
  const received = [];
  for (const client of [commandObserver, stateObserver, signalObserver]) {
    client.on('message', (topic, payload) => {
      if (payload.toString().includes('esp32-acl-denied')) received.push(topic);
    });
  }
  const publisher = connectAs('esp32');
  await waitFor(() => publisher.connected);
  publisher.publish('railway/commands/esp32', JSON.stringify({ marker: 'esp32-acl-denied' }));
  publisher.publish('railway/state', JSON.stringify({ marker: 'esp32-acl-denied' }));
  publisher.publish('railway/zone1/signal', JSON.stringify({ marker: 'esp32-acl-denied' }));
  await new Promise((resolve) => setTimeout(resolve, 500));
  assert.deepEqual(received, []);
  publisher.end(true); commandObserver.end(true); stateObserver.end(true); signalObserver.end(true);
});

test('godot can read esp32 telemetry but cannot publish it', async () => {
  const godot = connectAs('godot');
  await waitFor(() => godot.connected);
  await new Promise((resolve) => godot.subscribe('railway/telemetry/esp32', resolve));
  const seen = [];
  godot.on('message', (topic, payload) => seen.push([topic, payload.toString()]));

  const esp32 = connectAs('esp32');
  await waitFor(() => esp32.connected);
  esp32.publish('railway/telemetry/esp32', JSON.stringify({ marker: 'esp32-to-godot' }));
  await waitFor(() => seen.some(([, body]) => body.includes('esp32-to-godot')));
  assert.ok(seen.some(([topic, body]) => topic === 'railway/telemetry/esp32' && body.includes('esp32-to-godot')));

  const backendObserver = connectAs('backend');
  await waitFor(() => backendObserver.connected);
  await new Promise((resolve) => backendObserver.subscribe('railway/telemetry/esp32', resolve));
  const backendSeen = [];
  backendObserver.on('message', (topic, payload) => backendSeen.push(payload.toString()));

  godot.publish('railway/telemetry/esp32', JSON.stringify({ marker: 'godot-unauthorized' }));
  await new Promise((resolve) => setTimeout(resolve, 500));
  assert.ok(!backendSeen.some((body) => body.includes('godot-unauthorized')));

  godot.end(true); esp32.end(true); backendObserver.end(true);
});
