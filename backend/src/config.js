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
  topology: {
    lines: ['UP', 'DOWN'],
    blocksPerLine: 5,
    blockLengthM: 300,
    zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'],
    station: { id: 'station', name: 'Forest Halt', upIndex: 2, downIndex: 2, dwellSec: 20 },
  },
  trains: [
    { id: 'T1', line: 'UP', direction: 'UP', startBlock: 0, startOffsetM: 0, lengthM: 60 },
    { id: 'T2', line: 'UP', direction: 'UP', startBlock: 2, startOffsetM: 0, lengthM: 90 },
    { id: 'T3', line: 'DOWN', direction: 'DOWN', startBlock: 0, startOffsetM: 0, lengthM: 60 },
    { id: 'T4', line: 'DOWN', direction: 'DOWN', startBlock: 3, startOffsetM: 0, lengthM: 90 },
  ],
  simulation: {
    tickMs: 500,
    lookaheadBlocks: 2,
    cautionSpeedKmh: 30,
    brakeMps2: 2.0,
    accelMps2: 0.6,
    defaultTargetSpeedKmh: 48,
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
  if (!(c.simulation.tickMs > 0)) errors.push('simulation.tickMs must be > 0');
  if (errors.length) throw new Error(`invalid config: ${errors.join('; ')}`);
  return true;
}
