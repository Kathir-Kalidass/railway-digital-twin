import { Router } from 'express';
import { hasPermission } from '../rbac.js';
import { validateCommand, validateSpeed } from '../validate.js';

export function controlRouter({ auth, config, state, bus, audit, replay, mqtt }) {
  const router = Router();
  const ctx = { zones: config.zones };

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
    mqtt.publish(`railway/commands/${check.value.zone}`, check.value);
    const snapshot = bus.snapshot();
    audit.write({ actor: req.user.username, role: req.user.role, action: check.value.event, zone: check.value.zone, result: 'ACCEPTED', source: 'rest' });
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
    mqtt.publish(`railway/speed/${check.value.zone}`, { zone: check.value.zone, speedKmh: check.value.speedKmh, timestamp: new Date().toISOString() });
    const snapshot = bus.snapshot();
    audit.write({ actor: req.user.username, role: req.user.role, action: 'SPEED', zone: check.value.zone, target: String(check.value.speedKmh), result: 'ACCEPTED', source: 'rest' });
    return res.json({ ok: true, state: snapshot });
  });

  return router;
}
