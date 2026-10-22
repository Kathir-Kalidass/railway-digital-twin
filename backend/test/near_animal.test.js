import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildDeps, withServer } from './app_helpers.js';
import { config as defaultConfig } from '../src/config.js';

function headers(deps, eventId, capturedAt = new Date().toISOString()) {
  return {
    'content-type': 'image/jpeg',
    'x-camera-token': deps.config.cameraIngestToken,
    'x-train-id': 'T1',
    'x-line': 'UP',
    'x-block': 'UP-B0',
    'x-event-id': eventId,
    'x-captured-at': capturedAt,
  };
}

function commands(deps) {
  return deps.mqtt.published
    .filter((p) => p.t === 'railway/commands/esp32')
    .map((p) => p.o);
}

function post(url, deps, eventId, capturedAt) {
  return fetch(`${url}/api/wildlife/camera/frame`, {
    method: 'POST',
    headers: headers(deps, eventId, capturedAt),
    body: Buffer.from('jpeg'),
  });
}

test('one camera frame warns at 30 km/h without confirming', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const body = await (await post(url, deps, 'near-1')).json();
    assert.equal(body.confirmed, false);
    assert.equal(body.stage, 'SUSPECTED');
    const snap = deps.state.snapshot();
    const hazard = snap.blocks.find((b) => b.id === 'UP-B0').hazard;
    assert.equal(hazard.stage, 'SUSPECTED');
    assert.equal(hazard.confirmed, false);
    assert.ok(snap.trains[0].targetSpeedKmh <= 30);
    const sent = commands(deps);
    assert.equal(sent.filter((c) => c.event === 'WILDLIFE_NEAR').length, 1);
    assert.equal(sent.filter((c) => c.event === 'WILDLIFE_DETECTED').length, 0);
  });
});

test('the second frame within the window confirms and stops', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    await post(url, deps, 'near-2a');
    const second = await (await post(url, deps, 'near-2b')).json();
    assert.equal(second.confirmed, true);
    assert.equal(second.stage, 'CONFIRMED');
    const snap = deps.state.snapshot();
    assert.equal(snap.blocks.find((b) => b.id === 'UP-B0').hazard.stage, 'CONFIRMED');
    assert.equal(snap.trains[0].targetSpeedKmh, 0);
    const sent = commands(deps);
    assert.equal(sent.filter((c) => c.event === 'WILDLIFE_NEAR').length, 1);
    assert.equal(sent.filter((c) => c.event === 'WILDLIFE_DETECTED').length, 1);
  });
});

test('frames outside the confirmation window stay SUSPECTED', async () => {
  const deps = buildDeps({
    config: {
      ...defaultConfig,
      cameraConfirm: { ...defaultConfig.cameraConfirm, confirmWindowSec: 0.05 },
    },
  });
  await withServer(deps, async (url) => {
    await post(url, deps, 'near-3a');
    await new Promise((resolve) => setTimeout(resolve, 90));
    const second = await (await post(url, deps, 'near-3b')).json();
    assert.equal(second.confirmed, false);
    assert.equal(second.stage, 'SUSPECTED');
    assert.equal(deps.state.snapshot().blocks.find((b) => b.id === 'UP-B0').hazard.stage, 'SUSPECTED');
  });
});

test('near clear observation clears the warning and emits NEAR_CLEAR', () => {
  const deps = buildDeps();
  const near = {
    eventId: 'obs-near-1', source: 'onboard-camera', line: 'UP', distanceM: 100,
    wildlifeDetected: true, nearAnimal: true, confirmed: false,
    species: 'deer', count: 1, onTrack: true, trainId: 'T1', confidence: 0.7,
    timestamp: Date.now(),
  };
  deps.ingest.handle('railway/wildlife', near);
  assert.equal(deps.state.snapshot().blocks.find((b) => b.id === 'UP-B0').hazard.stage, 'SUSPECTED');
  assert.equal(commands(deps).filter((c) => c.event === 'WILDLIFE_NEAR').length, 1);

  deps.ingest.handle('railway/wildlife', {
    ...near, eventId: 'obs-near-2', wildlifeDetected: false, nearAnimal: false, confirmed: false, count: 0,
  });
  const snap = deps.state.snapshot();
  assert.equal(snap.blocks.find((b) => b.id === 'UP-B0').hazard, null);
  assert.equal(commands(deps).filter((c) => c.event === 'WILDLIFE_NEAR_CLEAR').length, 1);
});

test('clearing near evidence never clears a confirmed block', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    await post(url, deps, 'near-4a');
    await post(url, deps, 'near-4b');
    deps.ingest.handle('railway/wildlife', {
      eventId: 'near-4-clear', source: 'onboard-camera', line: 'UP', distanceM: 100,
      wildlifeDetected: false, nearAnimal: false, confirmed: false,
      species: 'deer', count: 0, onTrack: false, trainId: 'T1', confidence: 0.7,
      timestamp: Date.now(),
    });
    const snap = deps.state.snapshot();
    const hazard = snap.blocks.find((b) => b.id === 'UP-B0').hazard;
    assert.equal(hazard.stage, 'CONFIRMED');
    assert.equal(hazard.confirmed, true);
    assert.equal(snap.trains[0].targetSpeedKmh, 0);
    const sent = commands(deps);
    assert.equal(sent.filter((c) => c.event === 'WILDLIFE_NEAR_CLEAR').length, 0);
    assert.equal(sent.filter((c) => c.event === 'WILDLIFE_CLEARED').length, 0);
  });
});

test('a duplicate frame event id is ignored', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    await post(url, deps, 'near-dup');
    await post(url, deps, 'near-dup');
    const body = await (await post(url, deps, 'near-dup')).json();
    assert.equal(body.duplicate, true);
    assert.equal(deps.state.snapshot().blocks.find((b) => b.id === 'UP-B0').hazard.stage, 'SUSPECTED');
    assert.equal(commands(deps).filter((c) => c.event === 'WILDLIFE_NEAR').length, 1);
    assert.equal(commands(deps).filter((c) => c.event === 'WILDLIFE_DETECTED').length, 0);
  });
});

test('warning and stop do not depend on ESP32 command delivery', async () => {
  const deps = buildDeps();
  deps.bus.command = undefined;
  await withServer(deps, async (url) => {
    const first = await post(url, deps, 'near-offline-1');
    assert.equal(first.status, 200);
    assert.ok(deps.state.snapshot().trains[0].targetSpeedKmh <= 30);
    const second = await post(url, deps, 'near-offline-2');
    assert.equal(second.status, 200);
    assert.equal(deps.state.snapshot().trains[0].targetSpeedKmh, 0);
  });
});

test('a confirmed block never emits WILDLIFE_NEAR', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    await post(url, deps, 'near-5a');
    await post(url, deps, 'near-5b');
    await post(url, deps, 'near-5c');
    const sent = commands(deps);
    const nearIndex = sent.findIndex((c) => c.event === 'WILDLIFE_NEAR');
    const confirmedIndex = sent.findIndex((c) => c.event === 'WILDLIFE_DETECTED');
    assert.ok(nearIndex >= 0 && confirmedIndex > nearIndex);
    assert.equal(sent.slice(confirmedIndex).filter((c) => c.event === 'WILDLIFE_NEAR').length, 0);
  });
});

test('reset keeps the train stopped until the operator sets speed', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    await post(url, deps, 'near-reset-a');
    await post(url, deps, 'near-reset-b');
    assert.equal(deps.state.snapshot().trains[0].targetSpeedKmh, 0);
    assert.equal(deps.state.applyCommand({ zone: 'zone1', event: 'RESET' }).ok, true);
    deps.state.tick(0.5);
    let train = deps.state.snapshot().trains[0];
    assert.equal(train.targetSpeedKmh, 0);
    assert.equal(train.commandedSpeedKmh, 0);
    assert.equal(deps.state.applySpeed({ trainId: 'T1', speedKmh: 48 }).ok, true);
    deps.state.tick(0.5);
    train = deps.state.snapshot().trains[0];
    assert.equal(train.targetSpeedKmh, 48);
    assert.equal(train.commandedSpeedKmh, 48);
  });
});
