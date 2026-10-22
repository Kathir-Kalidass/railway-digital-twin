import { buildTopology, blockById } from './railway.js';
import { deriveBlockAspects, zoneSignal } from './signalling.js';
import { occupyBlocks, stepTrains } from './simulation.js';
import { makeRoutes } from './routes.js';
import { makeMeetScheduler } from './meets.js';

const DECEL = 2.0; // m/s^2 illustrative braking
const DEFAULT_TARGET = 48;
const DEFAULT_SIM = { lookaheadBlocks: 2, cautionSpeedKmh: 30, brakeMps2: 2.0, accelMps2: 0.6, defaultTargetSpeedKmh: DEFAULT_TARGET };

function newZone(id) {
  return {
    id, trainPresent: false, wildlifeDetected: false, sensorHealthy: true,
    signal: 'GREEN', status: 'NORMAL', targetSpeedKmh: DEFAULT_TARGET, blocks: [],
  };
}

export function makeState({ config, topology }) {
  const zones = {};
  for (const id of config.zones) zones[id] = newZone(id);

  const legacy = !config.topology;
  const topo = legacy ? null : (topology || buildTopology(config));
  const sim = config.simulation || DEFAULT_SIM;
  const comm = { mqttConnected: true }; // assume connected until told otherwise; server sets false at startup
  let lastEvent = 'System initialized';
  let tickCount = 0;

  const legacyTrain = { zone: config.zones[0], speedKmh: DEFAULT_TARGET, targetSpeedKmh: DEFAULT_TARGET, stoppingDistanceM: 0 };
  const trains = [];
  const blockHazards = {};
  let routes = null;
  let meets = null;

  if (topo) {
    for (const b of topo.blocks) {
      zones[b.zone].blocks.push(b.id);
      blockHazards[b.id] = {
        blockId: b.id,
        line: b.line,
        zone: b.zone,
        evidence: {
          trackside: null,
          onboard: null,
        },
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
    const outTrains = trains.map((t) => ({ ...t, stoppingDistanceM: stoppingDistanceM(t.speedKmh) }));
    return {
      zones: JSON.parse(JSON.stringify(zones)),
      train: outTrains[0] ? { ...outTrains[0] } : null, // DEPRECATED: summary of trains[0]
      trains: outTrains,
      lines: topo.lines.map((l) => ({ id: l.id, blocks: [...l.blocks] })),
      blocks: topo.blocks.map((b) => {
        const h = blockHazards[b.id];
        const activeSources = h?.active ? ['trackside', 'onboard'].filter((s) => h.evidence[s]?.active) : [];
        return {
          ...b,
          signal: aspects[b.id] || 'GREEN',
          hazard: h?.active ? { sources: activeSources, since: h.since } : null,
        };
      }),
      station: { ...topo.station, blocks: { ...topo.station.blocks } },
      routes: { active: routes.activeRoute(), available: routes.list() },
      meets: meets ? meets.snapshot() : null,
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
      case 'WILDLIFE_CLEARED':
        z.wildlifeDetected = false; z.status = 'RECOVERY_REQUIRED'; break;
      case 'SENSOR_FAULT':
        z.sensorHealthy = false; z.status = 'SENSOR_FAULT'; z.targetSpeedKmh = 0; break;
      case 'SENSOR_RESTORED':
        z.sensorHealthy = true; z.status = 'RECOVERY_REQUIRED'; break;
      case 'TRAIN_ENTERED_ZONE':
        z.trainPresent = true; if (legacy) legacyTrain.zone = env.zone; break;
      case 'TRAIN_LEFT_ZONE':
        z.trainPresent = false; break;
      case 'RESET':
        const hasActiveInZone = Object.values(blockHazards).some((h) => h.zone === env.zone && h.active);
        if (z.sensorHealthy && !z.wildlifeDetected && !hasActiveInZone) { z.status = 'NORMAL'; z.targetSpeedKmh = DEFAULT_TARGET; }
        else return { ok: false, reason: 'reset rejected: active hazard or sensor fault' };
        break;
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
    if (!topo || !comm.mqttConnected) return trains;
    tickCount += 1;
    if (meets) meets.tick(dtSec);
    routes.tick();
    const aspects = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones, blockHazards, lookaheadBlocks: sim.lookaheadBlocks });
    stepTrains({ topology: topo, simulation: sim, zones, trains, dtSec, aspects });
    occupyBlocks(topo, trains);
    return trains;
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
    const slot = obs.source === 'onboard-camera' ? 'onboard' : obs.source;
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
    } else {
      if (hazard.evidence[slot]) {
        hazard.evidence[slot] = { ...hazard.evidence[slot], active: false, at: obs.timestamp };
      } else {
        hazard.evidence[slot] = { active: false, at: obs.timestamp };
      }
    }

    const nowActive = Boolean(hazard.evidence.trackside?.active || hazard.evidence.onboard?.active);
    hazard.active = nowActive;
    if (nowActive && !wasActive) {
      hazard.since = new Date().toISOString();
      lastEvent = 'WILDLIFE_DETECTED';
    } else if (wasActive && !nowActive) {
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
      active: hazard.active,
      changed: wasActive !== nowActive,
    };
  }

  function markEvent(event) {
    lastEvent = String(event);
  }

  function setBrokerConnected(value) {
    comm.mqttConnected = Boolean(value);
  }

  return {
    snapshot, applyCommand, applySpeed, applyTelemetry,
    setSensor, setWildlife, applyWildlifeObservation,
    getBlockHazards: () => blockHazards,
    hasActiveHazard: (id) => Boolean(blockHazards[id]?.active),
    markEvent, setBrokerConnected,
    requestRoute, meetControl, tick, getTickCount: () => tickCount,
  };
}
