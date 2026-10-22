import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildDeps, withServer } from './app_helpers.js';

const headers = (config, extra = {}) => ({
  'content-type': 'image/jpeg',
  'x-camera-token': config.cameraIngestToken,
  'x-train-id': 'T1',
  'x-line': 'UP',
  'x-block': 'UP-B0',
  'x-event-id': 'evt-1',
  'x-captured-at': new Date().toISOString(),
  ...extra,
});

function suspect(deps) {
  deps.state.applyWildlifeObservation({
    eventId: 'evt-1', source: 'trackside', line: 'UP', distanceM: 100,
    wildlifeDetected: true, species: 'deer', count: 1, sensorId: 'UP-S0', timestamp: Date.now(),
  });
}

test('camera endpoint requires the machine token', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    suspect(deps);
    const res = await fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: { ...headers(deps.config), 'x-camera-token': 'wrong' }, body: Buffer.from('jpeg'),
    });
    assert.equal(res.status, 401);
  });
});

test('a single high-confidence frame warns but does not confirm', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    suspect(deps);
    const post = (id) => fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: headers(deps.config, { 'x-event-id': id }), body: Buffer.from('jpeg'),
    });
    const first = await (await post('evt-1a')).json();
    assert.equal(first.confirmed, false);
    assert.equal(first.stage, 'SUSPECTED');
    let snap = deps.state.snapshot();
    assert.equal(snap.blocks.find((b) => b.id === 'UP-B0').hazard.stage, 'SUSPECTED');
    assert.ok(snap.trains[0].targetSpeedKmh <= 30);

    const second = await (await post('evt-1b')).json();
    assert.equal(second.confirmed, true);
    snap = deps.state.snapshot();
    assert.equal(snap.blocks.find((b) => b.id === 'UP-B0').hazard.stage, 'CONFIRMED');
    assert.equal(snap.trains[0].targetSpeedKmh, 0);
  });
});

test('two consecutive 0.6 frames confirm, one alone does not', async () => {
  const deps = buildDeps({
    ml: {
      health: async () => ({ ok: true }),
      detect: async () => ({ model: 'stub', detections: [{ label: 'elephant', confidence: 0.6, box: [0, 0, 1, 1] }] }),
    },
  });
  await withServer(deps, async (url) => {
    suspect(deps);
    const post = (id) => fetch(`${url}/api/wildlife/camera/frame`, { method: 'POST', headers: headers(deps.config, { 'x-event-id': id }), body: Buffer.from('jpeg') });
    assert.equal((await (await post('evt-2a')).json()).confirmed, false);
    assert.equal((await (await post('evt-2b')).json()).confirmed, true);
  });
});

test('stale event is rejected without reactivating the hazard', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const res = await fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST',
      headers: headers(deps.config, { 'x-captured-at': new Date(Date.now() - 30_000).toISOString() }),
      body: Buffer.from('jpeg'),
    });
    assert.equal(res.status, 409);
  });
});

test('ML failure returns degraded and leaves the hazard SUSPECTED', async () => {
  const deps = buildDeps({
    ml: { health: async () => ({ ok: false }), detect: async () => { throw new Error('down'); } },
  });
  await withServer(deps, async (url) => {
    suspect(deps);
    const res = await fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: headers(deps.config), body: Buffer.from('jpeg'),
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.degraded, true);
    assert.equal(deps.state.snapshot().blocks.find((b) => b.id === 'UP-B0').hazard.stage, 'SUSPECTED');
  });
});
