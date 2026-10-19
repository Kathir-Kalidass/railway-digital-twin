export const COMMAND_EVENTS = new Set([
  'WILDLIFE_DETECTED', 'WILDLIFE_CLEARED', 'SENSOR_FAULT', 'SENSOR_RESTORED',
  'RESET', 'TRAIN_ENTERED_ZONE', 'TRAIN_LEFT_ZONE',
]);
const STALE_MS = 5 * 60 * 1000;

export function validateCommand(body, { zones }) {
  const request_id = String(body?.request_id || '');
  const zone = String(body?.zone || '').toLowerCase();
  const event = String(body?.event || '').toUpperCase();
  const timestamp = String(body?.timestamp || '');
  const source = String(body?.source || 'dashboard');
  const payload = body?.payload && typeof body.payload === 'object' ? body.payload : {};
  const errors = [];
  if (!request_id) errors.push('request_id required');
  if (!zones.includes(zone)) errors.push('invalid zone');
  if (!COMMAND_EVENTS.has(event)) errors.push('unsupported event');
  const ts = Date.parse(timestamp);
  if (Number.isNaN(ts)) errors.push('invalid timestamp');
  else if (Math.abs(Date.now() - ts) > STALE_MS) errors.push('stale timestamp');
  if (errors.length) return { ok: false, reason: errors.join('; ') };
  return { ok: true, value: { request_id, zone, event, timestamp, source, payload } };
}

export function validateSpeed(body, { zones }) {
  const zone = String(body?.zone || '').toLowerCase();
  const speedKmh = Number(body?.speedKmh);
  if (!zones.includes(zone)) return { ok: false, reason: 'invalid zone' };
  if (!Number.isFinite(speedKmh) || speedKmh < 0 || speedKmh > 80) {
    return { ok: false, reason: 'speed must be 0..80' };
  }
  return { ok: true, value: { zone, speedKmh } };
}
