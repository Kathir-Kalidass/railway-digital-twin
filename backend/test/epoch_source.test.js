import { test } from 'node:test';
import assert from 'node:assert/strict';
import { config } from '../src/config.js';
import { makeMqtt } from '../src/mqtt.js';
import { makeEpochSource } from '../src/epoch_source.js';
import { connectAs, waitFor } from './helpers/broker.js';

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
