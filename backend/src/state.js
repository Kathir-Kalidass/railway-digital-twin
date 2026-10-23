import { buildTopology, blockById } from './railway.js';
import { deriveBlockAspects, zoneSignal } from './signalling.js';
import { occupyBlocks, stepTrains } from './simulation.js';
import { makeRoutes } from './routes.js';
import { makeMeetScheduler } from './meets.js';
import { makeWrongLine } from './wrong_line.js';
import { blockOffsetToPhysical } from './geometry.js';

const DECEL = 2.0; // m/s^2 illustrative braking
const DEFAULT_TARGET = 48;
const DEFAULT_SIM = { lookaheadBlocks: 2, cautionSpeedKmh: 30, brakeMps2: 2.0, accelMps2: 0.6, defaultTargetSpeedKmh: DEFAULT_TARGET };

function newZone(id) {
  return {
    id, trainPresent: false, wildlifeDetected: false, sensorHealthy: true,
    signal: 'GREEN', status: 'NORMAL', targetSpeedKmh: DEFAULT_TARGET, blocks: [],
    esp32NearAnimal: false, esp32LastTelemetryAtMs: null,
  };
}

export function makeState({ config, topology, logEvent = null }) {
  const zones = {};
  for (const id of config.zones) zones[id] = newZone(id);

  const legacy = !config.topology;
  const topo = legacy ? null : (topology || buildTopology(config));
  const sim = config.simulation || DEFAULT_SIM;
  const comm = { mqttConnected: true }; // assume connected until told otherwise; server sets false at startup
  let lastEvent = 'System initialized';
  let tickCount = 0;
  const logSpeedRestore = (e) => {
    lastEvent = `Speed restored to ${e.restoredKmh} km/h for ${e.trainId}`;
    logEvent?.(e);
  };

  function markEsp32Telemetry(zone, atMs = Date.now()) {
    const z = zones[zone];
    if (!z) return;
    z.esp32LastTelemetryAtMs = atMs;
  }

  function esp32Snapshot() {
    const zone = config.esp32Zone || config.zones[0];
    const z = zones[zone];
    const atMs = z?.esp32LastTelemetryAtMs ?? null;
    const lastSeenSec = atMs !== null ? Math.floor((Date.now() - atMs) / 1000) : null;
    const timeoutSec = config.esp32TelemetryTimeoutSec;
    return {
      zone,
      online: lastSeenSec !== null && lastSeenSec <= timeoutSec,
      lastSeenSec,
      sensorHealthy: Boolean(z?.sensorHealthy),
      nearAnimal: z?.esp32NearAnimal === true,
    };
  }

  const legacyTrain = { zone: config.zones[0], speedKmh: DEFAULT_TARGET, targetSpeedKmh: DEFAULT_TARGET, stoppingDistanceM: 0 };
  const trains = [];
  const blockHazards = {};
  let routes = null;
  let meets = null;
  let wrongLine = null;

  if (topo) {
    for (const b of topo.blocks) {
      zones[b.zone].blocks.push(b.id);
      blockHazards[b.id] = {
        blockId: b.id,
        line: b.line,
        zone: b.zone,
        stage: 'NONE',
        confirmed: false,
        confidence: null,
        confirmedAt: null,
        confirmedBy: null,
        model: null,
        camera: null,
        evidence: {
          trackside: null,
          onboardSensor: null,
          camera: null,
        },
        sensorSources: [],
        active: false,
        since: null,
      };
    }
    for (const t of config.trains || []) {
      const block = blockById(topo, `${t.line}-B${t.startBlock}`);
      if (!block) continue;
      trains.push({
        id: t.id, line: t.line, direction: t.direction,
        block: block.id, offsetM: t.startOffsetM ?? 0,
        speedKmh: 0, targetSpeedKmh: zones[block.zone].targetSpeedKmh,
        commandedSpeedKmh: null, lengthM: t.lengthM,
        status: 'RUNNING', zone: block.zone,
        travelSign: t.line === 'DOWN' ? -1 : 1, operationalSign: 1,
      });
    }
    occupyBlocks(topo, trains);
    routes = makeRoutes({
      topology: topo,
      zones,
      trains,
      hasActiveHazard: (id) => Boolean(blockHazards[id]?.active),
    });
    meets = makeMeetScheduler({
      topology: topo,
      trains,
      zones,
      routes,
      hasActiveHazard: (id) => Boolean(blockHazards[id]?.active),
      config,
      onRestore: logSpeedRestore,
    });
    wrongLine = makeWrongLine({
      topology: topo,
      trains,
      zones,
      config,
      hasActiveHazard: (id) => Boolean(blockHazards[id]?.active),
      isMeetActive: () => Boolean(meets?.snapshot().active),
      onRestore: logSpeedRestore,
    });
  }

  const isRestrictive = (z) => z.wildlifeDetected || !z.sensorHealthy || z.status === 'RECOVERY_REQUIRED';

  function recompute() {
    for (const id of config.zones) zones[id].signal = zoneSignal(id, zones, blockHazards);
    const anyRestrictive = config.zones.some((id) => isRestrictive(zones[id]));
    const anyWildlife = config.zones.some((id) => zones[id].wildlifeDetected);
    const anyBlockHazard = Object.values(blockHazards).some((h) => h.active);
    const anyFault = config.zones.some((id) => !zones[id].sensorHealthy);
    if (!comm.mqttConnected) return 'COMM_LOST';
    if (anyFault) return 'SENSOR_FAULT';
    if (anyWildlife || anyBlockHazard) return 'HAZARD';
    if (anyRestrictive) return 'RECOVERY_REQUIRED';
    return 'NORMAL';
  }

  function stoppingDistanceM(speedKmh) {
    return Math.round((speedKmh / 3.6) ** 2 / (2 * DECEL));
  }

  function fleetSnapshot() {
    const aspects = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones, blockHazards, lookaheadBlocks: sim.lookaheadBlocks });
    for (const id of config.zones) {
      zones[id].trainPresent = trains.some((t) => t.zone === id);
      zones[id].blockHazards = Object.values(blockHazards).filter((h) => h.zone === id && h.active).map((h) => h.blockId);
    }
    const overall = recompute();
    const activeWrongLine = wrongLine ? wrongLine.snapshot().active : null;
    for (const t of trains) {
      const physical = Number.isFinite(t.physicalM) && t.routePhase
        ? t.physicalM
        : blockOffsetToPhysical(topo, t.line, t.block, t.offsetM);
      t.physicalM = physical;
      t.travelSign = Number.isFinite(t.travelSign) ? t.travelSign : (t.line === 'DOWN' ? -1 : 1);
      t.crossingProgress = t.routePhase === 'CROSS_ENTRY' || t.routePhase === 'CROSS_EXIT'
        ? (activeWrongLine?.crossingProgress ?? 0)
        : 0;
      t.crossoverId = t.routePhase === 'CROSS_ENTRY'
        ? activeWrongLine?.entryCrossover
        : t.routePhase === 'CROSS_EXIT'
          ? activeWrongLine?.exitCrossover
          : null;
      t.targetLine = t.routePhase === 'CROSS_ENTRY'
        ? activeWrongLine?.destinationLine
        : t.routePhase === 'CROSS_EXIT'
          ? activeWrongLine?.originalLine
          : null;
    }
    const outTrains = trains.map((t) => ({ ...t, stoppingDistanceM: stoppingDistanceM(t.speedKmh) }));
    return {
      zones: JSON.parse(JSON.stringify(zones)),
      train: outTrains[0] ? { ...outTrains[0] } : null, // DEPRECATED: summary of trains[0]
      trains: outTrains,
      lines: topo.lines.map((l) => ({ id: l.id, blocks: [...l.blocks] })),
      blocks: topo.blocks.map((b) => {
        const h = blockHazards[b.id];
        const activeSources = [];
        if (h?.active && h.evidence.trackside?.active) activeSources.push('trackside');
        if (h?.active && h.evidence.onboardSensor?.active) activeSources.push('onboard');
        if (h?.active && h.evidence.camera?.active) activeSources.push('camera');
        return {
          ...b,
          signal: aspects[b.id] || 'GREEN',
          hazard: h?.active ? {
            stage: h.stage,
            confirmed: h.confirmed,
            sources: activeSources,
            sensorSources: [...h.sensorSources],
            confidence: h.confidence,
            confirmedAt: h.confirmedAt,
            confirmedBy: h.confirmedBy,
            model: h.model,
            camera: h.camera,
            since: h.since,
          } : null,
        };
      }),
      station: { ...topo.station, blocks: { ...topo.station.blocks } },
      routes: {
        active: routes.activeRoute(),
        available: routes.list(),
        wrongLine: wrongLine ? wrongLine.snapshot() : { active: null, eligibility: {} },
      },
      meets: meets ? meets.snapshot() : null,
      esp32: esp32Snapshot(),
      comm: { ...comm },
      overall,
      lastEvent,
      updatedAt: new Date().toISOString(),
    };
  }

  function snapshot() {
    if (topo) return fleetSnapshot();
    const overall = recompute();
    legacyTrain.targetSpeedKmh = zones[legacyTrain.zone].targetSpeedKmh;
    legacyTrain.stoppingDistanceM = stoppingDistanceM(legacyTrain.speedKmh);
    return {
      zones: JSON.parse(JSON.stringify(zones)),
      train: { ...legacyTrain },
      esp32: esp32Snapshot(),
      comm: { ...comm },
      overall,
      lastEvent,
      updatedAt: new Date().toISOString(),
    };
  }

  function applyCommand(env) {
    const z = zones[env.zone];
    if (!z) return { ok: false, reason: 'unknown zone' };
    switch (env.event) {
      case 'WILDLIFE_DETECTED':
        z.wildlifeDetected = true; z.status = 'HAZARD'; z.targetSpeedKmh = 0; break;
      case 'WILDLIFE_CLEARED': {
        z.wildlifeDetected = false;
        z.status = 'RECOVERY_REQUIRED';
        for (const h of Object.values(blockHazards)) {
          if (h.zone !== env.zone) continue;
          if (h.evidence.trackside) h.evidence.trackside.active = false;
          if (h.evidence.onboardSensor) h.evidence.onboardSensor.active = false;
          h.sensorSources = Object.entries(h.evidence)
            .filter(([key, value]) => key !== 'camera' && value?.active)
            .map(([key]) => key);
          if (!h.confirmed) {
            h.stage = h.sensorSources.length > 0 ? 'SUSPECTED' : 'NONE';
            h.active = h.sensorSources.length > 0;
          }
        }
        break;
      }
      case 'SENSOR_FAULT':
        z.sensorHealthy = false; z.status = 'SENSOR_FAULT'; z.targetSpeedKmh = 0; break;
      case 'SENSOR_RESTORED':
        z.sensorHealthy = true; z.status = 'RECOVERY_REQUIRED'; break;
      case 'TRAIN_ENTERED_ZONE':
        z.trainPresent = true; if (legacy) legacyTrain.zone = env.zone; break;
      case 'TRAIN_LEFT_ZONE':
        z.trainPresent = false; break;
      case 'RESET': {
        const activeSensor = Object.values(blockHazards).some(
          (h) => h.zone === env.zone && h.sensorSources.length > 0,
        );
        if (z.sensorHealthy && !activeSensor && !z.wildlifeDetected) {
          z.status = 'NORMAL';
          z.targetSpeedKmh = DEFAULT_TARGET;
          z.wildlifeDetected = false;
          for (const h of Object.values(blockHazards)) {
            if (h.zone !== env.zone) continue;
            h.stage = 'NONE';
            h.confirmed = false;
            h.confidence = null;
            h.confirmedAt = null;
            h.confirmedBy = null;
            h.model = null;
            h.camera = null;
            h.sensorSources = [];
            h.evidence = { trackside: null, onboardSensor: null, camera: null };
            h.active = false;
            h.since = null;
          }
          for (const t of trains) {
            if (t.zone !== env.zone) continue;
            t.targetSpeedKmh = 0;
            t.commandedSpeedKmh = 0;
          }
        } else {
          return { ok: false, reason: 'reset rejected: active hazard or sensor fault' };
        }
        break;
      }
      default:
        return { ok: false, reason: 'unsupported event' };
    }
    lastEvent = env.event;
    return { ok: true };
  }

  function applySpeed({ zone, trainId, speedKmh }) {
    const v = Math.max(0, Math.min(80, Number(speedKmh)));
    if (trainId) {
      const t = trains.find((x) => x.id === trainId);
      if (!t) return { ok: false, reason: 'unknown train' };
      t.commandedSpeedKmh = v;
      t.targetSpeedKmh = v;
      return { ok: true };
    }
    const z = zones[zone];
    if (!z) return { ok: false, reason: 'unknown zone' };
    z.targetSpeedKmh = v;
    return { ok: true };
  }

  function applyTelemetry(zone, msg = {}) {
    const z = zones[zone];
    if (!z) return;
    if (typeof msg.wildlifeDetected === 'boolean') setWildlife(zone, msg.wildlifeDetected);
    if (typeof msg.sensorHealthy === 'boolean') z.sensorHealthy = msg.sensorHealthy;
    if (legacy) {
      if (typeof msg.trainPresent === 'boolean') z.trainPresent = msg.trainPresent;
      if (Number.isFinite(msg.speedKmh)) legacyTrain.speedKmh = Math.max(0, Math.min(80, msg.speedKmh));
    }
  }

  // Device telemetry is deliberately narrow: it cannot alter train telemetry
  // or block occupancy/aspects through the general compatibility adapter.
  function setSensor(zone, healthy) {
    const z = zones[zone];
    if (!z || typeof healthy !== 'boolean') return false;
    z.sensorHealthy = healthy;
    return true;
  }

  function setWildlife(zone, detected) {
    const z = zones[zone];
    if (!z || typeof detected !== 'boolean') return false;
    const wasActive = z.wildlifeDetected;
    z.wildlifeDetected = detected;
    if (detected) {
      if (z.sensorHealthy) z.status = 'HAZARD';
      z.targetSpeedKmh = 0;
    } else if (wasActive && z.sensorHealthy && z.status === 'HAZARD') {
      z.status = 'RECOVERY_REQUIRED';
    }
    return true;
  }

  function requestRoute({ trainId, routeId }) {
    if (!routes) return { ok: false, reason: 'routes unavailable' };
    return routes.requestRoute({ trainId, routeId });
  }

  function meetControl({ enabled, seed, trigger } = {}) {
    if (!meets) return { ok: false, reason: 'meets unavailable' };
    if (typeof enabled === 'boolean') meets.setEnabled(enabled);
    if (seed !== undefined) {
      if (!meets.setSeed(seed)) return { ok: false, reason: 'invalid seed' };
    }
    if (trigger === true && !meets.trigger()) return { ok: false, reason: 'meet not triggerable in current phase' };
    return { ok: true, meets: meets.snapshot() };
  }

  function tick(dtSec) {
    if (!topo || !comm.mqttConnected) return [];
    tickCount += 1;
    if (meets) meets.tick(dtSec);
    const routeEvents = wrongLine ? wrongLine.tick(dtSec) : [];
    routes.tick();
    const aspects = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones, blockHazards, lookaheadBlocks: sim.lookaheadBlocks });
    stepTrains({
      topology: topo, simulation: sim, zones, trains, dtSec, aspects, blockHazards,
      skipTrainIds: wrongLine ? wrongLine.skipIds() : [],
    });
    occupyBlocks(topo, trains);
    if (wrongLine) wrongLine.afterStep();
    for (const type of routeEvents) lastEvent = type;
    return routeEvents.map((type) => ({ type, ...(wrongLine?.snapshot().active || {}), time: new Date().toISOString() }));
  }

  function applyWildlifeObservation(obs) {
    if (!topo) return { ok: false, reason: 'topology unavailable' };
    const lineLen = topo.lines.find((l) => l.id === obs.line)?.lengthM || config.topology?.lineLengthM?.[obs.line] || 750;
    const numBlocks = config.topology?.blocksPerLine || 5;
    const blockLen = lineLen / numBlocks;
    const idx = Math.min(numBlocks - 1, Math.max(0, Math.floor(obs.distanceM / blockLen)));
    const blockId = `${obs.line}-B${idx}`;
    const hazard = blockHazards[blockId];
    if (!hazard) return { ok: false, reason: `unknown block ${blockId}` };

    const wasActive = hazard.active;
    const wasStage = hazard.stage;
    const slot = obs.source === 'trackside' ? 'trackside' : 'onboardSensor';
    if (obs.wildlifeDetected) {
      hazard.evidence[slot] = {
        active: true,
        species: obs.species,
        count: obs.count,
        eventId: obs.eventId,
        at: obs.timestamp,
        ...(obs.sensorId ? { sensorId: obs.sensorId } : {}),
        ...(obs.trainId ? { trainId: obs.trainId, confidence: obs.confidence } : {}),
      };
      if (obs.source === 'onboard-camera' && obs.trainId) {
        hazard.camera = {
          trainId: obs.trainId,
          species: obs.species,
          confidence: Number(obs.confidence),
          at: new Date(obs.timestamp).toISOString(),
        };
        hazard.evidence.camera = { active: true, ...hazard.camera };
      }
    } else {
      if (hazard.evidence[slot]) {
        hazard.evidence[slot] = { ...hazard.evidence[slot], active: false, at: obs.timestamp };
      }
      if (obs.source === 'onboard-camera' && hazard.evidence.camera) {
        hazard.evidence.camera = { ...hazard.evidence.camera, active: false, at: obs.timestamp };
      }
    }

    hazard.sensorSources = Object.entries(hazard.evidence)
      .filter(([key, value]) => key !== 'camera' && value?.active)
      .map(([key]) => key);
    const sensorActive = hazard.sensorSources.length > 0;
    if (obs.wildlifeDetected) {
      const near = obs.nearAnimal === true || hazard.stage === 'SUSPECTED';
      if (obs.confirmed === true) {
        hazard.confirmed = true;
        hazard.confidence = Number(obs.confidence);
        hazard.confirmedAt = new Date(obs.timestamp).toISOString();
        hazard.confirmedBy = obs.trainId || null;
      }
      if (hazard.confirmed) hazard.stage = 'CONFIRMED';
      else if (near && hazard.stage === 'NONE') hazard.stage = 'SUSPECTED';
      if (!hazard.confirmed && sensorActive) hazard.stage = 'SUSPECTED';
      hazard.active = hazard.confirmed || sensorActive || hazard.stage === 'SUSPECTED';
    } else {
      hazard.stage = hazard.confirmed ? 'CONFIRMED' : sensorActive ? 'SUSPECTED' : 'NONE';
      hazard.active = hazard.confirmed || sensorActive;
    }

    if (hazard.active && hazard.stage === 'SUSPECTED') {
      const z = zones[hazard.zone];
      const caution = config.nearAnimal?.serviceSpeedKmh ?? sim.cautionSpeedKmh ?? 30;
      if (z) {
        if (z.sensorHealthy) z.status = 'HAZARD';
        z.targetSpeedKmh = Math.min(z.targetSpeedKmh, caution);
      }
      for (const t of trains) {
        if (t.zone !== hazard.zone) continue;
        t.targetSpeedKmh = Math.min(t.targetSpeedKmh, caution);
      }
    }
    if (hazard.active && hazard.stage === 'CONFIRMED') {
      const z = zones[hazard.zone];
      if (z) {
        if (z.sensorHealthy) z.status = 'HAZARD';
        z.targetSpeedKmh = 0;
      }
      for (const t of trains) {
        if (t.zone === hazard.zone) t.targetSpeedKmh = 0;
      }
    }

    if (hazard.stage === 'CONFIRMED' && wasStage !== 'CONFIRMED') {
      lastEvent = 'WILDLIFE_CONFIRMED';
    } else if (hazard.active && !wasActive) {
      hazard.since = new Date().toISOString();
      lastEvent = hazard.stage === 'SUSPECTED' ? 'WILDLIFE_NEAR' : 'WILDLIFE_DETECTED';
    } else if (!hazard.active && wasActive) {
      const z = zones[hazard.zone];
      if (z && z.sensorHealthy && z.status !== 'SENSOR_FAULT') {
        z.status = 'RECOVERY_REQUIRED';
      }
      lastEvent = 'WILDLIFE_CLEARED';
    }

    return {
      ok: true,
      blockId,
      line: hazard.line,
      zone: hazard.zone,
      stage: hazard.stage,
      confirmed: hazard.confirmed,
      active: hazard.active,
      changed: wasActive !== hazard.active,
    };
  }

  function applyCameraNear({ line, blockId, trainId, species, confidence, bbox, capturedAt }) {
    const hazard = blockHazards[blockId];
    if (!hazard) return { ok: false, reason: `unknown block ${blockId}` };
    if (hazard.line !== line) return { ok: false, reason: 'line/block mismatch' };
    if (hazard.confirmed || hazard.stage === 'CONFIRMED') {
      return { ok: true, stage: 'CONFIRMED', changed: false, blockId };
    }
    const wasStage = hazard.stage;
    const at = capturedAt ? new Date(capturedAt).toISOString() : new Date().toISOString();
    hazard.active = true;
    hazard.stage = 'SUSPECTED';
    hazard.confidence = Number(confidence);
    hazard.camera = {
      trainId,
      species,
      confidence: Number(confidence),
      bbox: bbox || null,
      at,
    };
    hazard.evidence.camera = { active: true, ...hazard.camera };
    if (wasStage === 'NONE') hazard.since = at;
    const caution = config.nearAnimal?.serviceSpeedKmh ?? sim.cautionSpeedKmh ?? 30;
    const z = zones[hazard.zone];
    if (z) {
      if (z.sensorHealthy) z.status = 'HAZARD';
      z.targetSpeedKmh = Math.min(z.targetSpeedKmh, caution);
    }
    for (const t of trains) {
      if (t.zone !== hazard.zone) continue;
      t.targetSpeedKmh = Math.min(t.targetSpeedKmh, caution);
      if (t.commandedSpeedKmh != null) t.commandedSpeedKmh = Math.min(t.commandedSpeedKmh, caution);
    }
    lastEvent = 'WILDLIFE_NEAR';
    return { ok: true, stage: hazard.stage, changed: wasStage !== 'SUSPECTED', blockId, zone: hazard.zone };
  }

  function applyCameraConfirmation({ line, blockId, trainId, species, confidence, bbox, model, capturedAt }) {
    const hazard = blockHazards[blockId];
    if (!hazard) return { ok: false, reason: `unknown block ${blockId}` };
    if (hazard.line !== line) return { ok: false, reason: 'line/block mismatch' };
    if (!hazard.active && hazard.stage === 'NONE') return { ok: false, reason: 'stale hazard' };
    hazard.confirmed = true;
    hazard.active = true;
    hazard.stage = 'CONFIRMED';
    hazard.confidence = Number(confidence);
    hazard.confirmedAt = capturedAt ? new Date(capturedAt).toISOString() : new Date().toISOString();
    hazard.confirmedBy = trainId;
    hazard.model = model || null;
    hazard.camera = {
      trainId,
      species,
      confidence: Number(confidence),
      bbox: bbox || null,
      at: hazard.confirmedAt,
      frameId: null,
    };
    hazard.evidence.camera = {
      active: true,
      trainId,
      species,
      confidence: Number(confidence),
      bbox: bbox || null,
      at: hazard.confirmedAt,
      model: model || null,
    };
    const z = zones[hazard.zone];
    if (z) {
      if (z.sensorHealthy) z.status = 'HAZARD';
      z.targetSpeedKmh = 0;
    }
    for (const t of trains) {
      if (t.zone === hazard.zone) {
        t.targetSpeedKmh = 0;
        if (t.commandedSpeedKmh != null) t.commandedSpeedKmh = 0;
      }
    }
    lastEvent = 'WILDLIFE_CONFIRMED';
    return { ok: true, stage: hazard.stage, blockId };
  }

  function requestWrongLine({ trainId }) {
    if (!wrongLine) return { ok: false, reason: 'wrong-line unavailable' };
    const result = wrongLine.request({ trainId });
    if (result.ok) lastEvent = 'WRONG_LINE_GRANTED';
    return result;
  }

  function cancelWrongLine({ trainId }) {
    if (!wrongLine) return { ok: false, reason: 'wrong-line unavailable' };
    const result = wrongLine.cancel({ trainId });
    if (result.ok) lastEvent = 'WRONG_LINE_CANCELLED';
    return result;
  }

  function getWrongLine() {
    return wrongLine ? wrongLine.snapshot() : { active: null, eligibility: {}, lastEvent: null };
  }

  function getBlockHazard(blockId) {
    const h = blockHazards[blockId];
    return h ? { ...h, evidence: { ...h.evidence }, sensorSources: [...h.sensorSources] } : null;
  }

  function setEsp32NearAnimal(zone, value) {
    const z = zones[zone];
    if (z) z.esp32NearAnimal = Boolean(value);
  }

  function getCameraHealth() {
    return { enabled: Boolean(config.cameraConfirm?.enabled), ml: config.ml?.url || null };
  }

  function markEvent(event) {
    lastEvent = String(event);
  }

  function setBrokerConnected(value) {
    comm.mqttConnected = Boolean(value);
  }

  return {
    snapshot, applyCommand, applySpeed, applyTelemetry,
    setSensor, setWildlife, setEsp32NearAnimal, markEsp32Telemetry, applyWildlifeObservation, applyCameraNear, applyCameraConfirmation,
    getBlockHazards: () => blockHazards,
    getBlockHazard,
    getCameraHealth,
    hasActiveHazard: (id) => Boolean(blockHazards[id]?.active),
    markEvent, setBrokerConnected,
    requestRoute, meetControl, tick, getTickCount: () => tickCount,
    requestWrongLine, cancelWrongLine, getWrongLine,
  };
}
