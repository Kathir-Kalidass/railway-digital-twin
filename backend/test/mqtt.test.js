import { test } from 'node:test';
import assert from 'node:assert/strict';
import { config } from '../src/config.js';
import { makeMqtt } from '../src/mqtt.js';
import { connectAs, connectAnon, waitFor } from './helpers/broker.js';

test('connects with credentials and round-trips a publish', async () => {
  const bridge = makeMqtt({ config, onMessage: () => {} });
  await waitFor(() => bridge.isConnected());
  const sub = connectAs('dashboard'); // dashboard may read railway/state; godot may not
  await waitFor(() => sub.connected);
  const got = [];
  await new Promise((resolve) => sub.subscribe('railway/state', resolve));
  sub.on('message', (t, m) => got.push([t, m.toString()]));
  bridge.publish('railway/state', { ok: true }, { retain: true });
  await waitFor(() => got.some(([t]) => t === 'railway/state'));
  sub.end(true);
  bridge.close();
});

test('rejects anonymous connections', async () => {
  const client = connectAnon();
  const err = await new Promise((resolve) => {
    client.on('error', resolve);
    client.on('close', () => resolve(new Error('closed')));
  });
  assert.ok(err);
});
