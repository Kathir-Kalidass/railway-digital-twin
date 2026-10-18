import express from 'express';
import cors from 'cors';
import mqtt from 'mqtt';

const app = express();
app.use(cors());
app.use(express.json({ limit: '32kb' }));
const port = Number(process.env.PORT || 3001);
const mqttUrl = process.env.MQTT_URL || 'mqtt://127.0.0.1:1883';
const client = mqtt.connect(mqttUrl, { reconnectPeriod: 2000, connectTimeout: 5000 });
let state = {
  zone: 'ZONE_1', signal: 'GREEN', speedKmh: 48, targetSpeedKmh: 48,
  wildlifeDetected: false, sensorHealthy: true, barrier: 'OPEN', mode: 'AUTO',
  status: 'NORMAL', stoppingDistanceM: 0, lastEvent: 'System initialized',
  updatedAt: new Date().toISOString(), mqttConnected: false
};
const events = [];
function publish(topic, payload) {
  if (client.connected) client.publish(topic, JSON.stringify(payload), { qos: 0 });
}
function record(type, details = {}) {
  const e = { id: `${Date.now()}-${Math.random().toString(16).slice(2, 7)}`, time: new Date().toISOString(), type, ...details };
  events.unshift(e); if (events.length > 100) events.pop();
  state.lastEvent = type; state.updatedAt = e.time;
  publish('railway/events', e);
  return e;
}
function applyEvent(body = {}) {
  const type = String(body.type || 'STATUS').toUpperCase();
  if (type === 'WILDLIFE_DETECTED') {
    state.wildlifeDetected = true; state.signal = 'RED'; state.barrier = 'CLOSED'; state.status = 'HAZARD'; state.targetSpeedKmh = 0;
    record(type, { zone: body.zone || state.zone, source: body.source || 'simulation', severity: 'HIGH', message: 'Wildlife intrusion detected; restrictive signal requested.' });
  } else if (type === 'WILDLIFE_CLEARED') {
    state.wildlifeDetected = false;
    // Deliberately require explicit reset before restoring green.
    state.status = state.sensorHealthy ? 'RECOVERY_REQUIRED' : 'SENSOR_FAULT';
    record(type, { zone: body.zone || state.zone, source: body.source || 'simulation', message: 'Hazard clear reported; operator/reset recovery is still required.' });
  } else if (type === 'SENSOR_FAULT') {
    state.sensorHealthy = false; state.signal = 'RED'; state.barrier = 'CLOSED'; state.status = 'SENSOR_FAULT'; state.targetSpeedKmh = 0;
    record(type, { source: body.source || 'simulation', severity: 'HIGH', message: 'Sensor fault: restrictive state requested.' });
  } else if (type === 'SENSOR_RESTORED') {
    state.sensorHealthy = true; state.status = state.wildlifeDetected ? 'HAZARD' : 'RECOVERY_REQUIRED';
    record(type, { source: body.source || 'simulation', message: 'Sensor health restored; reset required before normal operation.' });
  } else if (type === 'RESET') {
    if (state.sensorHealthy && !state.wildlifeDetected) {
      state.signal = 'GREEN'; state.barrier = 'OPEN'; state.status = 'NORMAL'; state.targetSpeedKmh = 48;
      record(type, { source: body.source || 'dashboard', message: 'Scenario reset; normal simulated operation resumed.' });
    } else {
      record('RESET_REJECTED', { source: body.source || 'dashboard', message: 'Reset rejected: active hazard or sensor fault remains.' });
    }
  } else if (type === 'SIMULATION_TELEMETRY') {
    const reportedSpeed = Number(body.speedKmh);
    if (Number.isFinite(reportedSpeed)) state.speedKmh = Math.max(0, Math.min(80, reportedSpeed));
    state.zone = String(body.zone || state.zone);
    state.stoppingDistanceM = Math.round((state.speedKmh / 3.6) ** 2 / (2 * 1.2));
  } else if (type === 'SPEED') {
    const requested = Number(body.speedKmh);
    if (Number.isFinite(requested)) {
      state.targetSpeedKmh = Math.max(0, Math.min(80, requested));
      record('SPEED_CHANGED', { speedKmh: state.targetSpeedKmh, source: body.source || 'dashboard' });
    }
  } else {
    record(type, { ...body, message: body.message || 'Simulation event received.' });
  }
  state.updatedAt = new Date().toISOString();
  publish('railway/state', state);
  return state;
}
client.on('connect', () => { state.mqttConnected = true; publish('railway/state', state); client.subscribe('railway/telemetry'); });
client.on('reconnect', () => { state.mqttConnected = false; });
client.on('close', () => { state.mqttConnected = false; });
client.on('message', (topic, buffer) => {
  if (topic !== 'railway/telemetry') return;
  try {
    const t = JSON.parse(buffer.toString());
    if (typeof t.sensorHealthy === 'boolean' && !t.sensorHealthy) applyEvent({ type: 'SENSOR_FAULT', source: 'esp32' });
    else { state.controller = t; state.updatedAt = new Date().toISOString(); publish('railway/state', state); }
  } catch { record('INVALID_TELEMETRY', { source: 'mqtt', message: 'Invalid telemetry JSON ignored.' }); }
});
app.get('/api/health', (_req, res) => res.json({ ok: true, mqttConnected: client.connected }));
app.get('/api/state', (_req, res) => res.json({ ...state, mqttConnected: client.connected }));
app.get('/api/events', (_req, res) => res.json(events));
app.post('/api/event', (req, res) => {
  const allowed = new Set(['WILDLIFE_DETECTED','WILDLIFE_CLEARED','SENSOR_FAULT','SENSOR_RESTORED','RESET','SPEED','TRAIN_ENTERED_ZONE','TRAIN_LEFT_ZONE','SIMULATION_TELEMETRY']);
  const type = String(req.body?.type || '').toUpperCase();
  if (!allowed.has(type)) return res.status(400).json({ error: 'Unsupported event type' });
  res.json({ ok: true, state: applyEvent({ ...req.body, type }) });
});
app.post('/api/command', (req, res) => {
  const command = String(req.body?.command || '').toUpperCase();
  const allowed = new Set(['RESET','WILDLIFE_DETECTED','WILDLIFE_CLEARED','SENSOR_FAULT','SENSOR_RESTORED']);
  if (!allowed.has(command)) return res.status(400).json({ error: 'Unsupported command' });
  const next = applyEvent({ type: command, source: 'dashboard' });
  publish('railway/commands', { command, issuedAt: new Date().toISOString() });
  res.json({ ok: true, state: next });
});
app.post('/api/speed', (req, res) => {
  const speedKmh = Number(req.body?.speedKmh);
  if (!Number.isFinite(speedKmh) || speedKmh < 0 || speedKmh > 80) return res.status(400).json({ error: 'speedKmh must be between 0 and 80' });
  res.json({ ok: true, state: applyEvent({ type: 'SPEED', speedKmh, source: 'dashboard' }) });
});
app.listen(port, '0.0.0.0', () => console.log(`Railway bridge listening on :${port}; MQTT=${mqttUrl}`));
