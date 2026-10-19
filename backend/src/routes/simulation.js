import { Router } from 'express';

export function simulationRouter({ state, bus, audit, replay, config }) {
  const router = Router();

  router.post('/api/event', (req, res) => {
    const type = String(req.body?.type || '').toUpperCase();
    const zone = String(req.body?.zone || 'zone1').toLowerCase();
    const validZone = config.zones.includes(zone) ? zone : config.zones[0];

    if (type === 'SIMULATION_TELEMETRY') {
      const speedKmh = Number(req.body?.speedKmh);
      state.applyTelemetry(validZone, {
        trainPresent: req.body?.trainPresent ?? true,
        speedKmh: Number.isFinite(speedKmh) ? speedKmh : undefined,
        wildlifeDetected: typeof req.body?.wildlifeDetected === 'boolean' ? req.body.wildlifeDetected : undefined,
        sensorHealthy: typeof req.body?.sensorHealthy === 'boolean' ? req.body.sensorHealthy : undefined,
      });
      const snap = bus.snapshot();
      return res.json({ ok: true, state: snap });
    }

    // Direct simulation events from Godot twin
    const allowed = new Set([
      'WILDLIFE_DETECTED', 'WILDLIFE_CLEARED',
      'SENSOR_FAULT', 'SENSOR_RESTORED',
      'RESET', 'TRAIN_ENTERED_ZONE', 'TRAIN_LEFT_ZONE'
    ]);

    if (!allowed.has(type)) {
      if (type === 'SPEED') {
        const speedKmh = Number(req.body?.speedKmh);
        if (Number.isFinite(speedKmh)) {
          state.applySpeed({ zone: validZone, speedKmh });
          const snap = bus.snapshot();
          return res.json({ ok: true, state: snap });
        }
      }
      return res.status(400).json({ error: 'unsupported simulation event' });
    }

    const applied = state.applyCommand({ zone: validZone, event: type });
    if (!applied.ok) {
      audit.write({ actor: 'godot', role: 'simulation', action: type, zone: validZone, result: 'REJECTED', reason: applied.reason, source: 'godot' });
      return res.status(409).json({ error: 'transition rejected', reason: applied.reason });
    }

    audit.write({ actor: 'godot', role: 'simulation', action: type, zone: validZone, result: 'ACCEPTED', source: 'godot' });
    bus.event({ type, zone: validZone, source: 'godot', result: 'ACCEPTED' });
    const snap = bus.snapshot();
    return res.json({ ok: true, state: snap });
  });

  return router;
}
