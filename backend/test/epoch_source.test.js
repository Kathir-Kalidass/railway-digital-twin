import { test } from 'node:test';
import assert from 'node:assert/strict';
import { config } from '../src/config.js';
import { makeMqtt } from '../src/mqtt.js';
import { makeEpochSource } from '../src/epoch_source.js';
import { connectAs, waitFor } from './helpers/broker.js';
import { makeWildlifeCommands } from '../src/wildlife_commands.js';

test('esp32 commands carry the backend epoch anchor', () => {
  const fakeMqtt = { published: [], publish(t, o) { this.published.push([t, o]); } };
  const hazard = { zone: 'zone1', active: true, stage: 'CONFIRMED', blockId: 'UP-B2' };
  const cmds = makeWildlifeCommands({ state: { getBlockHazards: () => [hazard] }, bus: {}, config: { esp32Zone: 'zone1', zones: ['zone1'] }, mqtt: fakeMqtt });
  cmds.sync();
  const cmd = fakeMqtt.published.find(([t]) => t === 'railway/commands/esp32');
  assert.ok(cmd, 'command published');
  const [, envelope] = cmd;
  assert.ok(envelope.epochMs !== undefined, 'epochMs anchor present');
  assert.ok(Math.abs(envelope.epochMs - Date.now()) < 5000);
});

test('epoch source publishes a retained broker epoch', async () => {
  const bridge = makeMqtt({ config, onMessage: () => {} });
  await waitFor(() => bridge.isConnected());
  const epoch = makeEpochSource({ mqtt: bridge });
  await waitFor(() => bridge.isConnected());

  const sub = connectAs('esp32');
  await waitFor(() => sub.connected);
  const got = [];
  await new Promise((resolve) => sub.subscribe('railway/boot', resolve));
  sub.on('message', (t, m) => got.push([t, JSON.parse(m.toString())]));

  epoch.publishEpoch();
  await waitFor(() => got.some(([t, m]) => t === 'railway/boot' && m.event === 'BROKER_EPOCH' && Math.abs(m.epochMs - Date.now()) < 60_000));

  epoch.close();
  sub.end(true);
  bridge.close();
});

test('epoch source republishes on a timer', async () => {
  const published = [];
  const fakeTimer = (fn) => { fn(); return { unref() {}, ref() {} }; };
  const epoch = makeEpochSource({
    mqtt: { publish: (topic, obj, opts) => published.push([topic, obj, opts]) },
    onTimer: fakeTimer,
  });
  assert.ok(published.some(([t, m, o]) => t === 'railway/boot' && m.event === 'BROKER_EPOCH' && o.retain === true));
  epoch.close();
});
