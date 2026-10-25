import { buildTopology, blockById } from './railway.js';
import { blockOffsetToPhysical } from './geometry.js';

// Numeric env: undefined/garbage -> fallback; negative values rejected.
const finiteNumber = (raw, fallback) => {
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
};

export const config = {
  port: Number(process.env.PORT || 3001),
  mqttUrl: process.env.MQTT_URL || 'mqtt://127.0.0.1:1883',
  mqttUser: process.env.MQTT_BACKEND_USER || 'backend',
  mqttPass: process.env.MQTT_BACKEND_PASS || 'backend-dev-pass',
  jwtSecret: process.env.JWT_SECRET || 'dev-insecure-secret-change-me',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '1h',
  bcryptRounds: Number(process.env.BCRYPT_ROUNDS || 12),
  dbPath: process.env.DB_PATH || './data/railway.db',
  zones: ['zone1', 'zone2'],
  // One Stage D controller is explicitly assigned to this zone.
  esp32Zone: process.env.ESP32_ZONE || 'zone1',
  // ESP32 "online" is judged by telemetry freshness, never by broker connectivity.
  // Garbage env values must fall back to a safe default rather than NaN-degenerate checks.
  esp32TelemetryTimeoutSec: finiteNumber(process.env.ESP32_TELEMETRY_TIMEOUT_SEC, 15),
  // A command stays PENDING until matching ESP32 telemetry arrives; older pending entries time out.
  commandAckTimeoutSec: finiteNumber(process.env.COMMAND_ACK_TIMEOUT_SEC, 10),
  topology: {
    lines: ['UP', 'DOWN'],
    blocksPerLine: 5,
    blockLengthM: 300,
    lineLengthM: { UP: 1253.9822, DOWN: 1228.8495 },
    zoneByIndex: ['zone1', 'zone2', 'zone2', 'zone2', 'zone1'],
    station: { id: 'station', name: 'Forest Halt', upIndex: 0, downIndex: 4, dwellSec: 20 },
    crossovers: [
      { id: 'X-A', from: 'UP-B0', fromOffsetM: 120.0, to: 'DOWN-B4', toOffsetM: 125.7699, atM: 120.0 },
      { id: 'X-B', from: 'DOWN-B4', fromOffsetM: 5.7699, to: 'UP-B0', toOffsetM: 240.0, atM: 240.0 },
    ],
  },
  trains: [
    { id: 'T1', line: 'UP', direction: 'UP', startBlock: 0, startOffsetM: 0, lengthM: 60 },
    { id: 'T3', line: 'DOWN', direction: 'DOWN', startBlock: 3, startOffsetM: 71.5398, lengthM: 60 },
  ],
  wrongLine: {
    enabled: true,
    speedKmh: 30,
    approachMinM: 40,
    approachMaxM: 220,
    crossingLengthM: 20,
    holdBeforeEntryM: 80,
    stopMarginM: 25,
    timeoutSec: 120,
  },
  simulation: {
    tickMs: 500,
    lookaheadBlocks: 2,
    cautionSpeedKmh: 30,
    brakeMps2: 2.0,
    accelMps2: 0.6,
    defaultTargetSpeedKmh: 48,
  },
  cameraConfirm: {
    enabled: true,
    minConfidence: 0.5,
    confirmFrames: 2,
    confirmWindowSec: 2,
    cameraRangeM: 200,
    captureFps: 2,
    frameWidth: 640,
    frameHeight: 360,
    jpegQuality: 70,
    evidenceTtlSec: 86400,
  },
  ml: {
    url: process.env.ML_URL || 'http://127.0.0.1:8001',
    timeoutMs: Number(process.env.ML_TIMEOUT_MS || 2000),
  },
  nearAnimal: {
    enabled: true,
    serviceSpeedKmh: 30,
    confirmFrames: 2,
    confirmWindowSec: 2,
    nearHoldSec: 3,
    minWarningDistanceM: 40,
    leadFactor: 1.25,
    boxHeightRatio: 0.22,
    boxAreaRatio: 0.05,
    minBoxConfidence: 0.5,
  },
  cameraIngestToken: process.env.CAMERA_INGEST_TOKEN || 'dev-camera-token',
  cameraEvidenceDir: process.env.CAMERA_EVIDENCE_DIR || './data/camera-evidence',
  meets: {
    enabled: process.env.MEETS_ENABLED !== '0',
    seed: Number(process.env.MEET_SEED || 20261022),
    minGapSec: 60,
    maxGapSec: 180,
    stationWaitSec: 90,
    holdOffsetM: 80,
    minHoldSec: 6,
    maxHoldSec: 15,
    meetChance: 0.8,
    crossoverChance: 0,
    holdTimeoutSec: 25,
  },
  seedUsers: [
    { username: 'viewer', password: process.env.VIEWER_PASSWORD || 'viewer-dev-pass', role: 'viewer' },
    { username: 'operator', password: process.env.OPERATOR_PASSWORD || 'operator-dev-pass', role: 'operator' },
    { username: 'admin', password: process.env.ADMIN_PASSWORD || 'admin-dev-pass', role: 'admin' },
  ],
};

export function validateConfig(c) {
  const errors = [];
  const zones = new Set(c.zones);
  if (!zones.has(c.esp32Zone)) errors.push('esp32Zone unknown zone');
  for (const [i, z] of c.topology.zoneByIndex.entries()) if (!zones.has(z)) errors.push(`zoneByIndex[${i}] unknown zone ${z}`);
  for (const t of c.trains) {
    if (!c.topology.lines.includes(t.line)) errors.push(`train ${t.id} unknown line ${t.line}`);
    if (t.startBlock < 0 || t.startBlock >= c.topology.blocksPerLine) errors.push(`train ${t.id} startBlock out of range`);
    if (!(t.lengthM > 0)) errors.push(`train ${t.id} lengthM must be > 0`);
  }
  for (const line of c.topology.lines) {
    const length = c.topology.lineLengthM?.[line] ?? c.topology.blockLengthM * c.topology.blocksPerLine;
    if (!(length > 0)) errors.push(`topology lineLengthM.${line} must be > 0`);
  }
  const topo = buildTopology(c);
  for (const route of c.topology.crossovers || []) {
    if (!route.id) errors.push('crossover id required');
    for (const end of ['from', 'to']) {
      const id = route[end];
      const line = c.topology.lines.find((l) => l === id?.split('-')[0]);
      const index = Number(id?.split('-B')[1]);
      if (!line || !(index >= 0 && index < c.topology.blocksPerLine)) errors.push(`crossover ${route.id} unknown ${end} block ${id}`);
    }
    const from = blockById(topo, route.from);
    const to = blockById(topo, route.to);
    if (!from || !to) continue;
    if (!(route.fromOffsetM >= 0 && route.fromOffsetM < from.lengthM)) errors.push(`crossover ${route.id} fromOffsetM out of range`);
    if (!(route.toOffsetM >= 0 && route.toOffsetM < to.lengthM)) errors.push(`crossover ${route.id} toOffsetM out of range`);
    const fromPhysical = blockOffsetToPhysical(topo, from.line, from.id, route.fromOffsetM);
    const toPhysical = blockOffsetToPhysical(topo, to.line, to.id, route.toOffsetM);
    if (!(Math.abs(fromPhysical - route.atM) < 0.001) || !(Math.abs(toPhysical - route.atM) < 0.001)) {
      errors.push(`crossover ${route.id} atM does not match its offsets`);
    }
  }
  if (!(c.simulation.tickMs > 0)) errors.push('simulation.tickMs must be > 0');
  const meets = c.meets || {};
  if (meets.minGapSec != null && meets.maxGapSec != null && !(meets.minGapSec <= meets.maxGapSec)) {
    errors.push('meets gap range invalid');
  }
  for (const key of ['meetChance', 'crossoverChance']) {
    if (meets[key] != null && (meets[key] < 0 || meets[key] > 1)) errors.push(`meets.${key} must be 0..1`);
  }
  if (meets.holdOffsetM != null && meets.holdOffsetM < 0) errors.push('meets.holdOffsetM must be >= 0');
  const wl = c.wrongLine || {};
  if (wl.speedKmh != null && !(wl.speedKmh > 0)) errors.push('wrongLine.speedKmh must be > 0');
  if (wl.approachMinM != null && !(wl.approachMinM >= 0)) errors.push('wrongLine.approachMinM must be >= 0');
  if (wl.approachMaxM != null && wl.approachMinM != null && !(wl.approachMaxM > wl.approachMinM)) errors.push('wrongLine.approachMaxM must be > approachMinM');
  if (wl.crossingLengthM != null && !(wl.crossingLengthM > 0)) errors.push('wrongLine.crossingLengthM must be > 0');
  if (wl.holdBeforeEntryM != null && !(wl.holdBeforeEntryM >= 0)) errors.push('wrongLine.holdBeforeEntryM must be >= 0');
  if (wl.stopMarginM != null && !(wl.stopMarginM >= 0)) errors.push('wrongLine.stopMarginM must be >= 0');
  if (wl.timeoutSec != null && !(wl.timeoutSec > 0)) errors.push('wrongLine.timeoutSec must be > 0');
  if (errors.length) throw new Error(`invalid config: ${errors.join('; ')}`);
  return true;
}
