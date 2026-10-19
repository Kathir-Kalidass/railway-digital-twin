const DECEL = 1.2; // m/s^2 simulated braking
const DEFAULT_TARGET = 48;

function newZone(id) {
  return {
    id, trainPresent: false, wildlifeDetected: false, sensorHealthy: true,
    signal: 'GREEN', status: 'NORMAL', targetSpeedKmh: DEFAULT_TARGET,
  };
}

export function makeState({ config }) {
  const zones = {};
  for (const id of config.zones) zones[id] = newZone(id);
  const train = { zone: config.zones[0], speedKmh: DEFAULT_TARGET, targetSpeedKmh: DEFAULT_TARGET, stoppingDistanceM: 0 };
  const comm = { mqttConnected: true }; // assume connected until told otherwise; server sets false at startup
  let lastEvent = 'System initialized';

  const isRestrictive = (z) => z.wildlifeDetected || !z.sensorHealthy || z.status === 'RECOVERY_REQUIRED';

  function sectionFor(zone) {
    return Object.keys(zones).filter((id) => id !== zone && isRestrictive(zones[id])).length;
  }

  function recompute() {
    for (const id of config.zones) {
      const z = zones[id];
      if (isRestrictive(z)) z.signal = 'RED';
      else if (sectionFor(id) > 0) z.signal = 'YELLOW';
      else z.signal = 'GREEN';
    }
    const anyRestrictive = config.zones.some((id) => isRestrictive(zones[id]));
    const anyWildlife = config.zones.some((id) => zones[id].wildlifeDetected);
    const anyFault = config.zones.some((id) => !zones[id].sensorHealthy);
    if (!comm.mqttConnected) return 'COMM_LOST';
    if (anyFault) return 'SENSOR_FAULT';
    if (anyWildlife) return 'HAZARD';
    if (anyRestrictive) return 'RECOVERY_REQUIRED';
    return 'NORMAL';
  }

  function snapshot() {
    const overall = recompute();
    train.targetSpeedKmh = zones[train.zone].targetSpeedKmh;
    train.stoppingDistanceM = Math.round((train.speedKmh / 3.6) ** 2 / (2 * DECEL));
    return {
      zones: JSON.parse(JSON.stringify(zones)),
      train: { ...train },
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
        z.trainPresent = true; train.zone = env.zone; break;
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

  function applySpeed({ zone, speedKmh }) {
    const z = zones[zone];
    if (!z) return { ok: false, reason: 'unknown zone' };
    z.targetSpeedKmh = Math.max(0, Math.min(80, Number(speedKmh)));
    return { ok: true };
  }

  function applyTelemetry(zone, msg = {}) {
    const z = zones[zone];
    if (!z) return;
    if (typeof msg.trainPresent === 'boolean') z.trainPresent = msg.trainPresent;
    if (Number.isFinite(msg.speedKmh)) train.speedKmh = Math.max(0, Math.min(80, msg.speedKmh));
    if (typeof msg.wildlifeDetected === 'boolean') z.wildlifeDetected = msg.wildlifeDetected;
    if (typeof msg.sensorHealthy === 'boolean') z.sensorHealthy = msg.sensorHealthy;
  }

  function setBrokerConnected(value) {
    comm.mqttConnected = Boolean(value);
  }

  return { snapshot, applyCommand, applySpeed, applyTelemetry, setBrokerConnected };
}
