import mqtt from 'mqtt';

const URL = process.env.MQTT_URL || 'mqtt://127.0.0.1:1883';
const CREDS = {
  backend: [process.env.MQTT_BACKEND_USER || 'backend', process.env.MQTT_BACKEND_PASS || 'backend-dev-pass'],
  godot: ['godot', process.env.MQTT_GODOT_PASS || 'godot-dev-pass'],
  esp32: ['esp32', process.env.MQTT_ESP32_PASS || 'esp32-dev-pass'],
  dashboard: ['dashboard', process.env.MQTT_DASHBOARD_PASS || 'dashboard-dev-pass'],
};

export function waitFor(predicate, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const tick = () => {
      try { if (predicate()) return resolve(); } catch { /* keep polling */ }
      if (Date.now() - start > timeoutMs) return reject(new Error('waitFor timeout'));
      setTimeout(tick, 25);
    };
    tick();
  });
}

export function connectAs(role) {
  const [username, password] = CREDS[role];
  return mqtt.connect(URL, { username, password, reconnectPeriod: 0, connectTimeout: 4000 });
}

export function connectAnon() {
  return mqtt.connect(URL, { reconnectPeriod: 0, connectTimeout: 4000 });
}
