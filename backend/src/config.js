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
  seedUsers: [
    { username: 'viewer', password: process.env.VIEWER_PASSWORD || 'viewer-dev-pass', role: 'viewer' },
    { username: 'operator', password: process.env.OPERATOR_PASSWORD || 'operator-dev-pass', role: 'operator' },
    { username: 'admin', password: process.env.ADMIN_PASSWORD || 'admin-dev-pass', role: 'admin' },
  ],
};
