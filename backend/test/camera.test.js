import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
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

test('a frame larger than the ingest limit is rejected', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    suspect(deps);
    const res = await fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: headers(deps.config), body: Buffer.alloc(1_000_001),
    });
    assert.equal(res.status, 413);
  });
});

test('camera ingest enforces the per-train frame rate', async () => {
  const deps = buildDeps({
    ml: {
      health: async () => ({ ok: true }),
      detect: async () => ({
        model: 'stub',
        detections: [{ label: 'elephant', confidence: 0.9, box: [0.4, 0.4, 0.45, 0.45] }],
      }),
    },
  });
  await withServer(deps, async (url) => {
    suspect(deps);
    const post = (id) => fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: headers(deps.config, { 'x-event-id': id }), body: Buffer.from('jpeg'),
    });
    for (let i = 0; i < 5; i += 1) {
      assert.equal((await post(`rate-${i}`)).status, 200);
    }
    assert.equal((await post('rate-5')).status, 429);
  });
});

test('camera ingest rejects an unknown block or line mismatch', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const unknown = await fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: headers(deps.config, { 'x-block': 'UP-B9' }), body: Buffer.from('jpeg'),
    });
    assert.equal(unknown.status, 409);
    const body = await unknown.json();
    assert.equal(body.stale, true);
    assert.equal(body.stage, 'NONE');

    const mismatch = await fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: headers(deps.config, { 'x-line': 'DOWN' }), body: Buffer.from('jpeg'),
    });
    assert.equal(mismatch.status, 409);
    assert.equal((await mismatch.json()).stale, true);
  });
});

test('confirmation writes evidence, prunes the cap and audits', async () => {
  const deps = buildDeps();
  const evidenceDir = deps.config.cameraEvidenceDir;
  fs.mkdirSync(evidenceDir, { recursive: true });
  for (let i = 0; i < 51; i += 1) {
    fs.writeFileSync(path.join(evidenceDir, `old-${String(i).padStart(2, '0')}.jpg`), Buffer.from('old'));
  }
  await withServer(deps, async (url) => {
    suspect(deps);
    const post = (id) => fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: headers(deps.config, { 'x-event-id': id }), body: Buffer.from('confirming-jpeg'),
    });
    await post('evt-cap-a');
    assert.equal((await (await post('evt-cap-b')).json()).confirmed, true);

    const files = fs.readdirSync(evidenceDir);
    assert.ok(files.includes('evt-cap-b.jpg'));
    assert.ok(files.length <= 50, `evidence cap kept ${files.length} files`);
    assert.ok(deps.audit.list().some((row) => (
      row.action === 'WILDLIFE_CONFIRMED' && row.source === 'camera' && row.result === 'ACCEPTED'
    )));
  });
});
