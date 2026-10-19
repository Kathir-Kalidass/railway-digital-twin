import { Router } from 'express';
import { requirePermission } from '../rbac.js';

export function stateRouter({ auth, state, events, audit }) {
  const router = Router();
  router.get('/api/state', auth.requireAuth, requirePermission('state:read'), (_req, res) => res.json(state.snapshot()));
  router.get('/api/events', auth.requireAuth, requirePermission('events:read'), (_req, res) => res.json(events.list()));
  router.get('/api/audit', auth.requireAuth, requirePermission('audit:read'), (req, res) => res.json(audit.list(Number(req.query.limit) || 100)));
  return router;
}