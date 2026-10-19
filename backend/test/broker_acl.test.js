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

test('godot can publish zone telemetry', async () => {
  const observer = connectAs('backend'); // backend may read railway/zone1/train
  await waitFor(() => observer.connected);
  await new Promise((r) => observer.subscribe('railway/zone1/train', r));
  const seen = [];
  observer.on('message', (t) => seen.push(t));
  const godot = connectAs('godot');
  await waitFor(() => godot.connected);
  godot.publish('railway/zone1/train', JSON.stringify({ trainPresent: true }));
  await waitFor(() => seen.includes('railway/zone1/train'));
  assert.ok(seen.includes('railway/zone1/train'));
  godot.end(true); observer.end(true);
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
