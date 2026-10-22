import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateWildlifeObservation } from '../src/validate.js';
import { makeState } from '../src/state.js';
import { makeEvents } from '../src/events.js';
import { makeBus } from '../src/bus.js';
import { makeIngest } from '../src/ingest.js';
import { deriveBlockAspects, zoneSignal } from '../src/signalling.js';
import { buildTopology } from '../src/railway.js';
import { config as defaultConfig } from '../src/config.js';

function fakeMqtt() {
  return {
    published: [],
    publish(t, o, opts = {}) { this.published.push({ t, o, opts }); },
    subscribe() {},
    isConnected: () => true,
  };
}

test('validateWildlifeObservation accepts valid trackside and onboard observations', () => {
  const cfg = defaultConfig;
  const now = Date.now();
  const trackside = {
    eventId: 'trackside-UP-S2-1',
    source: 'trackside',
    line: 'UP',
    distanceM: 312.4,
    wildlifeDetected: true,
    species: 'deer',
    count: 1,
    onTrack: true,
    sensorId: 'UP-S2',
    timestamp: now / 1000,
  };
  const r1 = validateWildlifeObservation(trackside, cfg);
  assert.equal(r1.ok, true);
  assert.equal(r1.value.eventId, 'trackside-UP-S2-1');
  assert.equal(r1.value.source, 'trackside');

  const onboard = {
    eventId: 'onboard-T1-1',
    source: 'onboard-camera',
    line: 'DOWN',
    distanceM: 150.0,
    wildlifeDetected: true,
    species: 'elephant',
    count: 2,
    onTrack: true,
    trainId: 'T3',
    confidence: 0.85,
    timestamp: new Date().toISOString(),
  };
  const r2 = validateWildlifeObservation(onboard, cfg);
  assert.equal(r2.ok, true);
  assert.equal(r2.value.trainId, 'T3');
  assert.equal(r2.value.confidence, 0.85);

  const sensorObs = {
    eventId: 's1',
    source: 'onboard-sensor',
    line: 'UP',
    distanceM: 310,
    wildlifeDetected: true,
    trainId: 'T1',
    timestamp: now / 1000,
  };
  assert.equal(validateWildlifeObservation(sensorObs, cfg).ok, true);

  const near = {
    ...onboard,
    eventId: 'near-1',
    nearAnimal: true,
    confirmed: false,
  };
  const r3 = validateWildlifeObservation(near, cfg);
  assert.equal(r3.ok, true);
  assert.equal(r3.value.nearAnimal, true);
  assert.equal(r3.value.confirmed, false);

  const confirmed = {
    ...onboard,
    eventId: 'confirm-1',
    nearAnimal: false,
    confirmed: true,
  };
  const r4 = validateWildlifeObservation(confirmed, cfg);
  assert.equal(r4.ok, true);
  assert.equal(r4.value.confirmed, true);
});

test('validateWildlifeObservation rejects invalid, incomplete, or stale payloads', () => {
  const cfg = defaultConfig;
  const now = Date.now();
  // Missing eventId
  assert.equal(validateWildlifeObservation({ source: 'trackside', line: 'UP', distanceM: 100, wildlifeDetected: true, sensorId: 'S1', timestamp: now / 1000 }, cfg).ok, false);
  // Invalid source
  assert.equal(validateWildlifeObservation({ eventId: 'e1', source: 'drone', line: 'UP', distanceM: 100, wildlifeDetected: true, timestamp: now / 1000 }, cfg).ok, false);
  // Invalid line
  assert.equal(validateWildlifeObservation({ eventId: 'e2', source: 'trackside', line: 'SIDE', distanceM: 100, wildlifeDetected: true, sensorId: 'S1', timestamp: now / 1000 }, cfg).ok, false);
  // Stale timestamp (> 30s)
  assert.equal(validateWildlifeObservation({ eventId: 'e3', source: 'trackside', line: 'UP', distanceM: 100, wildlifeDetected: true, sensorId: 'S1', timestamp: (now - 35000) / 1000 }, cfg).ok, false);
  // distanceM out of range
  assert.equal(validateWildlifeObservation({ eventId: 'e4', source: 'trackside', line: 'UP', distanceM: 9999, wildlifeDetected: true, sensorId: 'S1', timestamp: now / 1000 }, cfg).ok, false);
  // Trackside missing sensorId
  assert.equal(validateWildlifeObservation({ eventId: 'e5', source: 'trackside', line: 'UP', distanceM: 100, wildlifeDetected: true, timestamp: now / 1000 }, cfg).ok, false);
  // Onboard missing trainId
  assert.equal(validateWildlifeObservation({ eventId: 'e6', source: 'onboard-camera', line: 'UP', distanceM: 100, wildlifeDetected: true, confidence: 0.9, timestamp: now / 1000 }, cfg).ok, false);
  // Onboard missing confidence
  assert.equal(validateWildlifeObservation({ eventId: 'e7', source: 'onboard-camera', line: 'UP', distanceM: 100, wildlifeDetected: true, trainId: 'T1', timestamp: now / 1000 }, cfg).ok, false);
  // Confirmation is only accepted from the onboard camera with a train id.
  assert.equal(validateWildlifeObservation({ eventId: 'e8', source: 'trackside', line: 'UP', distanceM: 100, wildlifeDetected: true, confirmed: true, sensorId: 'S1', timestamp: now / 1000 }, cfg).ok, false);
  assert.equal(validateWildlifeObservation({ eventId: 'e9', source: 'onboard-camera', line: 'UP', distanceM: 100, wildlifeDetected: true, confirmed: true, trainId: 'T1', confidence: 0.9, nearAnimal: 'yes', timestamp: now / 1000 }, cfg).ok, false);
});

test('state manages dual evidence on block hazards independently and enforces recovery', () => {
  const state = makeState({ config: defaultConfig });
  state.setBrokerConnected(true);

  // UP line length is 1253.9822, 5 blocks per line -> block length ~250.796m
  // distance 620m is in block UP-B2 (indices 0: 0-250.8, 1: 250.8-501.6, 2: 501.6-752.4)
  const tracksideObs = {
    eventId: 'e-track-1',
    source: 'trackside',
    line: 'UP',
    distanceM: 620,
    wildlifeDetected: true,
    species: 'deer',
    count: 1,
    onTrack: true,
    sensorId: 'UP-S2',
    timestamp: Date.now() / 1000,
  };

  const res1 = state.applyWildlifeObservation(tracksideObs);
  assert.equal(res1.ok, true);
  assert.equal(res1.blockId, 'UP-B2');
  assert.equal(res1.active, true);

  let snap = state.snapshot();
  assert.equal(snap.overall, 'HAZARD');
  const upB2 = snap.blocks.find((b) => b.id === 'UP-B2');
  assert.ok(upB2.hazard);
  assert.deepEqual(upB2.hazard.sources, ['trackside']);

  // Onboard camera also observes wildlife in UP-B2
  const onboardObs = {
    eventId: 'e-cam-1',
    source: 'onboard-camera',
    line: 'UP',
    distanceM: 640,
    wildlifeDetected: true,
    species: 'deer',
    count: 1,
    onTrack: true,
    trainId: 'T1',
    confidence: 0.88,
    timestamp: Date.now() / 1000,
  };

  const res2 = state.applyWildlifeObservation(onboardObs);
  assert.equal(res2.ok, true);
  snap = state.snapshot();
  const upB2Dual = snap.blocks.find((b) => b.id === 'UP-B2');
  assert.deepEqual(upB2Dual.hazard.sources.sort(), ['camera', 'onboard', 'trackside']);

  // Trackside clears: hazard must remain active because onboard is still active!
  const tracksideClear = {
    ...tracksideObs,
    eventId: 'e-track-2',
    wildlifeDetected: false,
    count: 0,
    timestamp: Date.now() / 1000,
  };
  state.applyWildlifeObservation(tracksideClear);
  snap = state.snapshot();
  const upB2StillActive = snap.blocks.find((b) => b.id === 'UP-B2');
  assert.ok(upB2StillActive.hazard);
  assert.deepEqual(upB2StillActive.hazard.sources.sort(), ['camera', 'onboard']);
  assert.equal(snap.overall, 'HAZARD');

  // RESET attempted while onboard is still active must be rejected
  const resetAttempt = state.applyCommand({ zone: 'zone2', event: 'RESET' });
  assert.equal(resetAttempt.ok, false);

  // Onboard clears: all evidence clear -> block enters recovery, zone enters RECOVERY_REQUIRED
  const onboardClear = {
    ...onboardObs,
    eventId: 'e-cam-2',
    wildlifeDetected: false,
    count: 0,
    timestamp: Date.now() / 1000,
  };
  state.applyWildlifeObservation(onboardClear);
  snap = state.snapshot();
  const upB2Cleared = snap.blocks.find((b) => b.id === 'UP-B2');
  assert.equal(upB2Cleared.hazard, null);
  assert.equal(snap.zones.zone2.status, 'RECOVERY_REQUIRED');
  assert.equal(snap.overall, 'RECOVERY_REQUIRED');

  // Now RESET succeeds
  const resetSuccess = state.applyCommand({ zone: 'zone2', event: 'RESET' });
  assert.equal(resetSuccess.ok, true);
  snap = state.snapshot();
  assert.equal(snap.zones.zone1.status, 'NORMAL');
  assert.equal(snap.overall, 'NORMAL');
});

test('sensor evidence is SUSPECTED, camera confirmation is CONFIRMED', () => {
  const cfg = {
    ...defaultConfig,
    trains: [
      { ...defaultConfig.trains[0], startBlock: 2, startOffsetM: 50 },
      defaultConfig.trains[1],
    ],
  };
  const state = makeState({ config: cfg });
  state.setBrokerConnected(true);
  const now = Date.now();

  state.applyWildlifeObservation({
    eventId: 's1', source: 'trackside', line: 'UP', distanceM: 300,
    wildlifeDetected: true, species: 'deer', count: 1, sensorId: 'UP-S1', timestamp: now,
  });
  let snap = state.snapshot();
  let hazard = snap.blocks.find((b) => b.id === 'UP-B1').hazard;
  assert.equal(hazard.stage, 'SUSPECTED');
  assert.equal(hazard.confirmed, false);
  assert.deepEqual(hazard.sensorSources, ['trackside']);
  assert.equal(snap.blocks.find((b) => b.id === 'UP-B1').signal, 'YELLOW');

  state.applyCameraConfirmation({
    line: 'UP', blockId: 'UP-B1', trainId: 'T1', species: 'elephant',
    confidence: 0.91, bbox: [0.1, 0.2, 0.5, 0.6], model: 'stub',
  });
  snap = state.snapshot();
  hazard = snap.blocks.find((b) => b.id === 'UP-B1').hazard;
  assert.equal(hazard.stage, 'CONFIRMED');
  assert.equal(hazard.confirmed, true);
  assert.equal(hazard.confidence, 0.91);
  assert.equal(hazard.camera.trainId, 'T1');
  assert.equal(snap.blocks.find((b) => b.id === 'UP-B1').signal, 'RED');
  assert.equal(snap.trains[0].targetSpeedKmh, 0);

  state.applyWildlifeObservation({
    eventId: 's2', source: 'trackside', line: 'UP', distanceM: 300,
    wildlifeDetected: false, species: 'deer', count: 0, sensorId: 'UP-S1', timestamp: now + 1000,
  });
  snap = state.snapshot();
  hazard = snap.blocks.find((b) => b.id === 'UP-B1').hazard;
  assert.equal(hazard.stage, 'CONFIRMED', 'confirmation stays latched after sensors clear');

  state.applyCommand({ zone: 'zone2', event: 'RESET' });
  snap = state.snapshot();
  hazard = snap.blocks.find((b) => b.id === 'UP-B1').hazard;
  assert.equal(hazard, null);
  assert.equal(snap.zones.zone2.status, 'NORMAL');
});

test('signalling sets hazard block RED, approach YELLOW, leaving other line unaffected', () => {
  const topo = buildTopology(defaultConfig);
  const blocks = topo.blocks.map((b) => ({ ...b, occupiedBy: null }));
  const zones = {
    zone1: { id: 'zone1', signal: 'GREEN', status: 'NORMAL', wildlifeDetected: false, sensorHealthy: true },
    zone2: { id: 'zone2', signal: 'GREEN', status: 'NORMAL', wildlifeDetected: false, sensorHealthy: true },
  };
  const blockHazards = {
    'UP-B2': {
      blockId: 'UP-B2',
      line: 'UP',
      zone: 'zone1',
      active: true,
      stage: 'CONFIRMED',
      evidence: { trackside: { active: true }, onboardSensor: null, camera: null },
    },
  };

  const aspects = deriveBlockAspects({ topology: topo, blocks, zones, blockHazards, lookaheadBlocks: 2 });
  assert.equal(aspects['UP-B2'], 'RED'); // Hazard block
  assert.equal(aspects['UP-B1'], 'YELLOW'); // Block immediately behind UP-B2
  assert.equal(aspects['UP-B0'], 'GREEN'); // Further behind
  assert.equal(aspects['UP-B3'], 'GREEN'); // Ahead of hazard
  assert.equal(aspects['UP-B4'], 'GREEN'); // Further ahead

  // DOWN line is completely unaffected
  for (let i = 0; i < 5; i++) {
    assert.equal(aspects[`DOWN-B${i}`], 'GREEN');
  }

  // A confirmed block hazard makes its zone RED and the other zone cautious.
  assert.equal(zoneSignal('zone1', zones, blockHazards), 'RED');
  assert.equal(zoneSignal('zone2', zones, blockHazards), 'YELLOW');
});

test('routes through hazard block are rejected', () => {
  const state = makeState({ config: defaultConfig });
  state.setBrokerConnected(true);

  // Put a hazard on the route's station block.
  const obs = {
    eventId: 'e-haz-1',
    source: 'trackside',
    line: 'UP',
    distanceM: 100, // UP-B0
    wildlifeDetected: true,
    sensorId: 'UP-S0',
    timestamp: Date.now() / 1000,
  };
  state.applyWildlifeObservation(obs);

  // Request crossover X-A (from UP-B0 to DOWN-B4)
  const routeRes = state.requestRoute({ trainId: 'T1', routeId: 'X-A' });
  assert.equal(routeRes.ok, false);
  assert.ok(routeRes.reason.includes('hazard'));
});

test('ingest forwards edge-triggered alert to railway/commands/esp32 when hazard in esp32Zone', () => {
  const mqtt = fakeMqtt();
  const state = makeState({ config: defaultConfig });
  const bus = makeBus({ mqtt, state, events: makeEvents() });
  const ingest = makeIngest({ state, bus, config: defaultConfig, mqtt });
  ingest.onBrokerConnected(true);

  const obs = {
    eventId: 'e-track-edge-1',
    source: 'trackside',
    line: 'UP',
    distanceM: 100, // UP-B0 is in zone1 (esp32Zone)
    wildlifeDetected: true,
    species: 'deer',
    count: 1,
    onTrack: true,
    sensorId: 'UP-S2',
    timestamp: Date.now() / 1000,
  };

  ingest.handle('railway/wildlife', obs);

  const espCmds = mqtt.published.filter((m) => m.t === 'railway/commands/esp32');
  assert.ok(espCmds.length >= 1);
  const nearCmd = espCmds[espCmds.length - 1].o;
  assert.equal(nearCmd.event, 'WILDLIFE_NEAR');
  assert.equal(nearCmd.source, 'backend');
  assert.equal(nearCmd.payload.blockId, 'UP-B0');

  // Duplicate observation with same eventId is dropped without second edge
  ingest.handle('railway/wildlife', obs);
  assert.equal(mqtt.published.filter((m) => m.t === 'railway/commands/esp32').length, 1);

  // Clear near warning: sends WILDLIFE_NEAR_CLEAR
  const clearObs = {
    ...obs,
    eventId: 'e-track-edge-2',
    wildlifeDetected: false,
    count: 0,
    timestamp: Date.now() / 1000,
  };
  ingest.handle('railway/wildlife', clearObs);

  const clearCmds = mqtt.published.filter((m) => m.t === 'railway/commands/esp32');
  assert.equal(clearCmds.length, 2);
  const clearedCmd = clearCmds[1].o;
  assert.equal(clearedCmd.event, 'WILDLIFE_NEAR_CLEAR');
  assert.equal(clearedCmd.source, 'backend');
});
