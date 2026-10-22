import { Router } from 'express';
import { hasPermission } from '../rbac.js';
import { validateWrongLineRequest } from '../validate.js';

export function wrongLineRouter({ auth, config, state, bus, audit, replay }) {
  const router = Router();
  const trainIds = (config.trains || []).map((t) => t.id);

  router.get('/api/routes/wrong-line', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'state:read')) return res.status(403).json({ error: 'forbidden' });
    return res.json(state.getWrongLine());
  });

  router.post('/api/routes/wrong-line', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'route:set')) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE', result: 'FORBIDDEN', reason: 'missing route:set', source: 'rest' });
      return res.status(403).json({ error: 'forbidden' });
    }
    const check = validateWrongLineRequest(req.body, { trainIds });
    if (!check.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE', result: 'REJECTED', reason: check.reason, source: 'rest' });
      return res.status(400).json({ error: 'invalid wrong-line request', reason: check.reason });
    }
    const dedupe = replay.check(check.value.request_id, { username: req.user.username, action: 'WRONG_LINE' });
    if (!dedupe.ok) return res.status(400).json({ error: 'duplicate', reason: dedupe.reason });
    const applied = state.requestWrongLine(check.value);
    if (!applied.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE', target: check.value.trainId, result: 'REJECTED', reason: applied.reason, source: 'rest' });
      return res.status(409).json({ error: 'wrong-line rejected', reason: applied.reason });
    }
    audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE', target: check.value.trainId, result: 'ACCEPTED', source: 'rest' });
    bus.event({ type: 'WRONG_LINE_GRANTED', trainId: check.value.trainId, actor: req.user.username });
    return res.json({ ok: true, route: applied.route, state: bus.snapshot() });
  });

  router.post('/api/routes/wrong-line/cancel', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'route:set')) return res.status(403).json({ error: 'forbidden' });
    const check = validateWrongLineRequest(req.body, { trainIds });
    if (!check.ok) return res.status(400).json({ error: 'invalid cancel', reason: check.reason });
    const applied = state.cancelWrongLine(check.value);
    if (!applied.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE_CANCEL', target: check.value.trainId, result: 'REJECTED', reason: applied.reason, source: 'rest' });
      return res.status(409).json({ error: 'cancel rejected', reason: applied.reason });
    }
    audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE_CANCEL', target: check.value.trainId, result: 'ACCEPTED', source: 'rest' });
    bus.event({ type: 'WRONG_LINE_CANCELLED', trainId: check.value.trainId, actor: req.user.username });
    return res.json({ ok: true, state: bus.snapshot() });
  });

  return router;
}
