import { buildTopology, blockById } from './railway.js';
import { deriveBlockAspects, zoneSignal } from './signalling.js';
import { occupyBlocks, stepTrains } from './simulation.js';
import { makeRoutes } from './routes.js';

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
  let routes = null;

  if (topo) {
    for (const b of topo.blocks) zones[b.zone].blocks.push(b.id);
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
    routes = makeRoutes({ topology: topo, zones, trains });
  }

  const isRestrictive = (z) => z.wildlifeDetected || !z.sensorHealthy || z.status === 'RECOVERY_REQUIRED';

  function recompute() {
    for (const id of config.zones) zones[id].signal = zoneSignal(id, zones);
    const anyRestrictive = config.zones.some((id) => isRestrictive(zones[id]));
    const anyWildlife = config.zones.some((id) => zones[id].wildlifeDetected);
    const anyFault = config.zones.some((id) => !zones[id].sensorHealthy);
    if (!comm.mqttConnected) return 'COMM_LOST';
    if (anyFault) return 'SENSOR_FAULT';
    if (anyWildlife) return 'HAZARD';
    if (anyRestrictive) return 'RECOVERY_REQUIRED';
    return 'NORMAL';
  }

  function stoppingDistanceM(speedKmh) {
    return Math.round((speedKmh / 3.6) ** 2 / (2 * DECEL));
  }

  function fleetSnapshot() {
    const aspects = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones, lookaheadBlocks: sim.lookaheadBlocks });
    for (const id of config.zones) zones[id].trainPresent = trains.some((t) => t.zone === id);
    const overall = recompute();
    const outTrains = trains.map((t) => ({ ...t, stoppingDistanceM: stoppingDistanceM(t.speedKmh) }));
    return {
      zones: JSON.parse(JSON.stringify(zones)),
      train: outTrains[0] ? { ...outTrains[0] } : null, // DEPRECATED: summary of trains[0]
      trains: outTrains,
      lines: topo.lines.map((l) => ({ id: l.id, blocks: [...l.blocks] })),
      blocks: topo.blocks.map((b) => ({ ...b, signal: aspects[b.id] || 'GREEN' })),
      station: { ...topo.station, blocks: { ...topo.station.blocks } },
      routes: { active: routes.activeRoute(), available: routes.list() },
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
        if (z.sensorHealthy && !z.wildlifeDetected) { z.status = 'NORMAL'; z.targetSpeedKmh = DEFAULT_TARGET; }
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

  function tick(dtSec) {
    if (!topo || !comm.mqttConnected) return trains;
    tickCount += 1;
    routes.tick();
    const aspects = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones, lookaheadBlocks: sim.lookaheadBlocks });
    stepTrains({ topology: topo, simulation: sim, zones, trains, dtSec, aspects });
    occupyBlocks(topo, trains);
    return trains;
  }

  function markEvent(event) {
    lastEvent = String(event);
  }

  function setBrokerConnected(value) {
    comm.mqttConnected = Boolean(value);
  }

  return {
    snapshot, applyCommand, applySpeed, applyTelemetry,
    setSensor, setWildlife, markEvent, setBrokerConnected,
    requestRoute, tick, getTickCount: () => tickCount,
  };
}
