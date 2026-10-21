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
});

test('state manages dual evidence on block hazards independently and enforces recovery', () => {
  const state = makeState({ config: defaultConfig });
  state.setBrokerConnected(true);

  // UP line length is 753.9822, 5 blocks per line -> block length ~150.796m
  // distance 310m is in block UP-B2 (indices 0: 0-150.8, 1: 150.8-301.6, 2: 301.6-452.4)
  const tracksideObs = {
    eventId: 'e-track-1',
    source: 'trackside',
    line: 'UP',
    distanceM: 310,
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
    distanceM: 320,
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
  assert.deepEqual(upB2Dual.hazard.sources.sort(), ['onboard', 'trackside']);

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
  assert.deepEqual(upB2StillActive.hazard.sources, ['onboard']);
  assert.equal(snap.overall, 'HAZARD');

  // RESET attempted while onboard is still active must be rejected
  const resetAttempt = state.applyCommand({ zone: 'zone1', event: 'RESET' });
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
  assert.equal(snap.zones.zone1.status, 'RECOVERY_REQUIRED');
  assert.equal(snap.overall, 'RECOVERY_REQUIRED');

  // Now RESET succeeds
  const resetSuccess = state.applyCommand({ zone: 'zone1', event: 'RESET' });
  assert.equal(resetSuccess.ok, true);
  snap = state.snapshot();
  assert.equal(snap.zones.zone1.status, 'NORMAL');
  assert.equal(snap.overall, 'NORMAL');
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
      evidence: { trackside: { active: true }, onboard: null },
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

  // zoneSignal for zone1 with block hazard alone is YELLOW (informational, not RED)
  assert.equal(zoneSignal('zone1', zones, blockHazards), 'YELLOW');
  assert.equal(zoneSignal('zone2', zones, blockHazards), 'YELLOW'); // cross-zone caution
});

test('routes through hazard block are rejected', () => {
  const state = makeState({ config: defaultConfig });
  state.setBrokerConnected(true);

  // Position T1 at UP-B2
  const obs = {
    eventId: 'e-haz-1',
    source: 'trackside',
    line: 'UP',
    distanceM: 310, // UP-B2
    wildlifeDetected: true,
    sensorId: 'UP-S2',
    timestamp: Date.now() / 1000,
  };
  state.applyWildlifeObservation(obs);

  // Request crossover X-UP-DOWN (from UP-B2 to DOWN-B2)
  const routeRes = state.requestRoute({ trainId: 'T1', routeId: 'X-UP-DOWN' });
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
    distanceM: 310, // UP-B2 is in zone1 (esp32Zone)
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
  const detectedCmd = espCmds[espCmds.length - 1].o;
  assert.equal(detectedCmd.event, 'WILDLIFE_DETECTED');
  assert.equal(detectedCmd.source, 'backend');
  assert.equal(detectedCmd.payload.blockId, 'UP-B2');

  // Duplicate observation with same eventId is dropped without second edge
  ingest.handle('railway/wildlife', obs);
  assert.equal(mqtt.published.filter((m) => m.t === 'railway/commands/esp32').length, 1);

  // Clear hazard: sends WILDLIFE_CLEARED
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
  assert.equal(clearedCmd.event, 'WILDLIFE_CLEARED');
  assert.equal(clearedCmd.source, 'backend');
});
