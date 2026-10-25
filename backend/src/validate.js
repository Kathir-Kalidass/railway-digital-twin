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
  return { ok: true, value: { request_id, zone, event, timestamp, source, epochMs: Date.now(), payload } };
}

export function validateSpeed(body, { zones, trainIds = [] }) {
  const speedKmh = Number(body?.speedKmh);
  const trainId = String(body?.trainId || '');
  if (trainId) {
    if (!trainIds.includes(trainId)) return { ok: false, reason: 'unknown train' };
    if (!Number.isFinite(speedKmh) || speedKmh < 0 || speedKmh > 80) {
      return { ok: false, reason: 'speed must be 0..80' };
    }
    return { ok: true, value: { trainId, speedKmh } };
  }
  const zone = String(body?.zone || '').toLowerCase();
  if (!zones.includes(zone)) return { ok: false, reason: 'invalid zone' };
  if (!Number.isFinite(speedKmh) || speedKmh < 0 || speedKmh > 80) {
    return { ok: false, reason: 'speed must be 0..80' };
  }
  return { ok: true, value: { zone, speedKmh } };
}

export function validateRoute(body, { trainIds = [], routeIds = [] }) {
  const request_id = String(body?.request_id || '');
  const trainId = String(body?.trainId || '');
  const routeId = String(body?.routeId || '');
  const errors = [];
  if (!request_id) errors.push('request_id required');
  if (!trainIds.includes(trainId)) errors.push('unknown train');
  if (!routeIds.includes(routeId)) errors.push('unknown route');
  if (errors.length) return { ok: false, reason: errors.join('; ') };
  return { ok: true, value: { request_id, trainId, routeId } };
}

export function validateWildlifeObservation(body, config = {}) {
  const eventId = String(body?.eventId || '');
  const source = String(body?.source || '');
  const line = String(body?.line || '');
  const wildlifeDetected = body?.wildlifeDetected;
  const distanceM = Number(body?.distanceM);
  const timestamp = body?.timestamp;
  const species = String(body?.species || 'wildlife');
  const count = body?.count != null ? Number(body.count) : (wildlifeDetected ? 1 : 0);
  const onTrack = body?.onTrack != null ? Boolean(body.onTrack) : Boolean(wildlifeDetected);
  const nearAnimal = body?.nearAnimal === true;
  const confirmed = body?.confirmed === true;

  const errors = [];
  if (body?.nearAnimal !== undefined && typeof body.nearAnimal !== 'boolean') errors.push('nearAnimal must be boolean');
  if (body?.confirmed !== undefined && typeof body.confirmed !== 'boolean') errors.push('confirmed must be boolean');
  if (confirmed && (source !== 'onboard-camera' || !String(body?.trainId || ''))) {
    errors.push('confirmed requires onboard-camera and trainId');
  }
  if (!eventId) errors.push('eventId required');
  if (!['trackside', 'onboard-sensor', 'onboard-camera'].includes(source)) errors.push('source must be trackside, onboard-sensor or onboard-camera');

  const validLines = config.topology?.lines || ['UP', 'DOWN'];
  if (!validLines.includes(line)) errors.push(`invalid line ${line}`);

  if (typeof wildlifeDetected !== 'boolean') errors.push('wildlifeDetected must be boolean');

  const lineLengths = config.topology?.lineLengthM || { UP: 1253.9822, DOWN: 1228.8495 };
  const maxLen = lineLengths[line] || 10000;
  if (!Number.isFinite(distanceM) || distanceM < 0 || distanceM >= maxLen) {
    errors.push(`distanceM out of range [0, ${maxLen})`);
  }

  let tsMs = NaN;
  if (typeof timestamp === 'number') {
    tsMs = timestamp < 1e11 ? timestamp * 1000 : timestamp;
  } else if (typeof timestamp === 'string') {
    tsMs = Date.parse(timestamp);
  }
  if (Number.isNaN(tsMs)) {
    errors.push('invalid timestamp');
  } else if (Math.abs(Date.now() - tsMs) > 30 * 1000) {
    errors.push('stale timestamp');
  }

  if (count < 0 || !Number.isInteger(count)) errors.push('count must be non-negative integer');

  let sensorId = null;
  let trainId = null;
  let confidence = null;

  if (source === 'trackside') {
    sensorId = String(body?.sensorId || '');
    if (!sensorId) errors.push('sensorId required for trackside');
  } else if (source === 'onboard-sensor' || source === 'onboard-camera') {
    trainId = String(body?.trainId || '');
    if (!trainId) errors.push(`trainId required for ${source}`);
    if (source === 'onboard-camera') {
      confidence = Number(body?.confidence);
      if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
        errors.push('confidence must be number in 0..1 for onboard-camera');
      }
    }
  }

  if (errors.length) return { ok: false, reason: errors.join('; ') };
  return {
    ok: true,
    value: {
      eventId,
      source,
      line,
      distanceM,
      wildlifeDetected,
      species,
      count,
      onTrack,
      nearAnimal,
      confirmed,
      timestamp: tsMs,
      ...(sensorId ? { sensorId } : {}),
      ...(trainId ? { trainId, confidence } : {}),
    },
  };
}

export function validateWrongLineRequest(body, { trainIds = [] } = {}) {
  const trainId = String(body?.trainId || '');
  const request_id = String(body?.request_id || '');
  const errors = [];
  if (!request_id) errors.push('request_id required');
  if (!trainIds.includes(trainId)) errors.push('unknown train');
  if (errors.length) return { ok: false, reason: errors.join('; ') };
  return { ok: true, value: { request_id, trainId } };
}

export function validateMeet(body) {
  const request_id = String(body?.request_id || '');
  const errors = [];
  if (!request_id) errors.push('request_id required');
  if (body?.enabled !== undefined && typeof body.enabled !== 'boolean') errors.push('enabled must be boolean');
  if (body?.seed !== undefined && !Number.isFinite(Number(body.seed))) errors.push('seed must be a finite number');
  if (body?.trigger !== undefined && typeof body.trigger !== 'boolean') errors.push('trigger must be boolean');
  if (errors.length) return { ok: false, reason: errors.join('; ') };
  return {
    ok: true,
    value: {
      request_id,
      enabled: body?.enabled,
      seed: body?.seed === undefined ? undefined : Number(body.seed),
      trigger: body?.trigger,
    },
  };
}
