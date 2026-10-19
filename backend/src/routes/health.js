import { Router } from 'express';

export function healthRouter({ mqtt }) {
  const router = Router();
  router.get('/api/health', (_req, res) => res.json({ ok: true, mqttConnected: mqtt.isConnected() }));
  return router;
}
