import { Router } from 'express';
import { hasPermission } from '../rbac.js';
import { validateCommand, validateMeet, validateRoute, validateSpeed } from '../validate.js';

export function controlRouter({ auth, config, state, bus, audit, replay, mqtt, commandTracker }) {
  const router = Router();
  const ctx = {
    zones: config.zones,
    trainIds: (config.trains || []).map((t) => t.id),
    routeIds: (config.topology?.crossovers || []).map((r) => r.id),
  };

  function deny(req, res, action, zone, reason) {
    audit.write({ actor: req.user.username, role: req.user.role, action, zone, result: 'FORBIDDEN', reason, source: 'rest' });
    bus.security({ request_id: req.body?.request_id || null, actor: req.user.username, reason, timestamp: new Date().toISOString() });
    return res.status(403).json({ error: 'forbidden', reason });
  }

  router.post('/api/control', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'control:issue')) {
      return deny(req, res, String(req.body?.event || 'UNKNOWN'), req.body?.zone || null, 'missing control:issue');
    }
    const check = validateCommand(req.body, ctx);
    if (!check.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: String(req.body?.event || 'UNKNOWN'), zone: req.body?.zone || null, result: 'REJECTED', reason: check.reason, source: 'rest' });
      bus.security({ request_id: req.body?.request_id || null, actor: req.user.username, reason: check.reason, timestamp: new Date().toISOString() });
      return res.status(400).json({ error: 'invalid command', reason: check.reason });
    }
    const dedupe = replay.check(check.value.request_id, { username: req.user.username, action: check.value.event });
    if (!dedupe.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: check.value.event, zone: check.value.zone, result: 'REJECTED', reason: dedupe.reason, source: 'rest' });
      bus.security({ request_id: check.value.request_id, actor: req.user.username, reason: dedupe.reason, timestamp: new Date().toISOString() });
      return res.status(400).json({ error: 'duplicate', reason: dedupe.reason });
    }
    const applied = state.applyCommand(check.value);
    if (!applied.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: check.value.event, zone: check.value.zone, result: 'REJECTED', reason: applied.reason, source: 'rest' });
      bus.security({ request_id: check.value.request_id, actor: req.user.username, reason: applied.reason, timestamp: new Date().toISOString() });
      return res.status(409).json({ error: 'transition rejected', reason: applied.reason });
    }
    audit.write({ actor: req.user.username, role: req.user.role, action: check.value.event, zone: check.value.zone, result: 'ACCEPTED', source: 'rest' });
    mqtt.publish(`railway/commands/${check.value.zone}`, check.value);
    if (config.esp32Zone && config.esp32Zone === check.value.zone) {
      mqtt.publish('railway/commands/esp32', check.value);
      // Ledgered as PENDING; only a matching ESP32 telemetry response flips it to ACKNOWLEDGED.
      commandTracker?.issued({
        requestId: check.value.request_id,
        event: check.value.event,
        zone: check.value.zone,
        actor: req.user.username,
        at: Date.now(),
      });
    }
    const snapshot = bus.snapshot();
    bus.event({ type: check.value.event, zone: check.value.zone, actor: req.user.username, result: 'ACCEPTED' });
    return res.json({ ok: true, state: snapshot });
  });

  router.post('/api/speed', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'speed:set')) {
      return deny(req, res, 'SPEED', req.body?.zone || null, 'missing speed:set');
    }
    const check = validateSpeed(req.body, ctx);
    if (!check.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'SPEED', zone: req.body?.zone || null, result: 'REJECTED', reason: check.reason, source: 'rest' });
      bus.security({ request_id: req.body?.request_id || null, actor: req.user.username, reason: check.reason, timestamp: new Date().toISOString() });
      return res.status(400).json({ error: 'invalid speed', reason: check.reason });
    }
    state.applySpeed(check.value);
    const snapshot = bus.snapshot();
    const zone = check.value.zone || snapshot.trains?.find((t) => t.id === check.value.trainId)?.zone || null;
    if (zone) {
      mqtt.publish(`railway/speed/${zone}`, { zone, trainId: check.value.trainId || null, speedKmh: check.value.speedKmh, timestamp: new Date().toISOString() });
    }
    audit.write({ actor: req.user.username, role: req.user.role, action: 'SPEED', zone, target: String(check.value.speedKmh), result: 'ACCEPTED', source: 'rest' });
    return res.json({ ok: true, state: snapshot });
  });

  router.post('/api/route', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'route:set')) {
      return deny(req, res, 'ROUTE', null, 'missing route:set');
    }
    const check = validateRoute(req.body, ctx);
    if (!check.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'ROUTE', zone: null, result: 'REJECTED', reason: check.reason, source: 'rest' });
      bus.security({ request_id: req.body?.request_id || null, actor: req.user.username, reason: check.reason, timestamp: new Date().toISOString() });
      return res.status(400).json({ error: 'invalid route', reason: check.reason });
    }
    const dedupe = replay.check(check.value.request_id, { username: req.user.username, action: 'ROUTE' });
    if (!dedupe.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'ROUTE', zone: null, result: 'REJECTED', reason: dedupe.reason, source: 'rest' });
      bus.security({ request_id: check.value.request_id, actor: req.user.username, reason: dedupe.reason, timestamp: new Date().toISOString() });
      return res.status(400).json({ error: 'duplicate', reason: dedupe.reason });
    }
    const applied = state.requestRoute(check.value);
    if (!applied.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'ROUTE', zone: null, result: 'REJECTED', reason: applied.reason, source: 'rest' });
      bus.security({ request_id: check.value.request_id, actor: req.user.username, reason: applied.reason, timestamp: new Date().toISOString() });
      return res.status(409).json({ error: 'route rejected', reason: applied.reason });
    }
    audit.write({ actor: req.user.username, role: req.user.role, action: 'ROUTE', zone: null, result: 'ACCEPTED', source: 'rest' });
    const snapshot = bus.snapshot();
    bus.event({ type: 'ROUTE_GRANTED', trainId: check.value.trainId, routeId: check.value.routeId, actor: req.user.username, result: 'ACCEPTED' });
    return res.json({ ok: true, route: applied.route, state: snapshot });
  });

  router.post('/api/meet', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'route:set')) {
      return deny(req, res, 'MEET', null, 'missing route:set');
    }
    const check = validateMeet(req.body);
    if (!check.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'MEET', zone: null, result: 'REJECTED', reason: check.reason, source: 'rest' });
      bus.security({ request_id: req.body?.request_id || null, actor: req.user.username, reason: check.reason, timestamp: new Date().toISOString() });
      return res.status(400).json({ error: 'invalid meet control', reason: check.reason });
    }
    const dedupe = replay.check(check.value.request_id, { username: req.user.username, action: 'MEET' });
    if (!dedupe.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'MEET', zone: null, result: 'REJECTED', reason: dedupe.reason, source: 'rest' });
      bus.security({ request_id: check.value.request_id, actor: req.user.username, reason: dedupe.reason, timestamp: new Date().toISOString() });
      return res.status(400).json({ error: 'duplicate', reason: dedupe.reason });
    }
    const applied = state.meetControl({
      enabled: check.value.enabled,
      seed: check.value.seed,
      trigger: check.value.trigger,
    });
    if (!applied.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'MEET', zone: null, result: 'REJECTED', reason: applied.reason, source: 'rest' });
      return res.status(409).json({ error: 'meet rejected', reason: applied.reason });
    }
    audit.write({ actor: req.user.username, role: req.user.role, action: 'MEET', zone: null, result: 'ACCEPTED', source: 'rest' });
    bus.event({ type: 'MEET_CONTROL', result: 'ACCEPTED', actor: req.user.username });
    return res.json({ ok: true, state: bus.snapshot() });
  });

  return router;
}
