import { Router } from 'express';
import express from 'express';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

function safeEqual(a, b) {
  const left = Buffer.from(String(a || ''));
  const right = Buffer.from(String(b || ''));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

export function wildlifeRouter({ config, state, bus, audit, ml, commands }) {
  const router = Router();
  const frameTimes = new Map();
  const streaks = new Map();
  const seenEventIds = new Set();
  const evidenceDir = config.cameraEvidenceDir || './data/camera-evidence';
  const nearConfig = config.nearAnimal || {};
  const cameraConfig = config.cameraConfirm || {};

  router.get('/api/wildlife/camera/health', async (_req, res) => {
    try {
      if (!ml) throw new Error('ml unavailable');
      const health = await ml.health();
      return res.json({ ok: true, ...state.getCameraHealth(), ml: health });
    } catch {
      return res.json({ ok: false, degraded: true, ...state.getCameraHealth() });
    }
  });

  router.post(
    '/api/wildlife/camera/frame',
    express.raw({ type: 'image/jpeg', limit: '1mb' }),
    async (req, res) => {
      if (!safeEqual(req.get('x-camera-token'), config.cameraIngestToken)) {
        return res.status(401).json({ error: 'unauthorized camera' });
      }
      const trainId = String(req.get('x-train-id') || '');
      const line = String(req.get('x-line') || '');
      const blockId = String(req.get('x-block') || '');
      const eventId = String(req.get('x-event-id') || '');
      const capturedAt = String(req.get('x-captured-at') || '');
      if (!trainId || !line || !blockId || !eventId || !capturedAt) {
        return res.status(400).json({ error: 'missing camera headers' });
      }
      if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
        return res.status(400).json({ error: 'empty jpeg' });
      }
      if (req.body.length > 1_000_000) return res.status(413).json({ error: 'frame too large' });
      const capturedMs = Date.parse(capturedAt);
      if (Number.isNaN(capturedMs) || Math.abs(Date.now() - capturedMs) > 10_000) {
        return res.status(409).json({ ok: false, stale: true, stage: 'STALE_CAPTURE' });
      }
      if (seenEventIds.has(eventId)) {
        return res.json({ ok: true, duplicate: true, confirmed: false });
      }
      seenEventIds.add(eventId);
      if (seenEventIds.size > 512) seenEventIds.delete(seenEventIds.values().next().value);

      const now = Date.now();
      const recent = (frameTimes.get(trainId) || []).filter((t) => now - t < 1000);
      if (recent.length >= (config.cameraConfirm?.captureFps || 2) * 2.5) {
        return res.status(429).json({ error: 'frame rate exceeded' });
      }
      recent.push(now);
      frameTimes.set(trainId, recent);

      const hazard = state.getBlockHazard(blockId);
      if (!hazard || hazard.line !== line) {
        return res.status(409).json({ ok: false, stale: true, stage: hazard?.stage || 'NONE' });
      }

      let result;
      try {
        if (!ml) throw new Error('ml unavailable');
        result = await ml.detect(req.body);
      } catch {
        bus.alert({
          source: 'ml',
          severity: 'MEDIUM',
          message: 'ML unavailable; hazard remains SUSPECTED',
          timestamp: new Date().toISOString(),
        });
        return res.json({ ok: true, confirmed: false, degraded: true, stage: 'SUSPECTED' });
      }

      const detections = (result.detections || [])
        .filter((d) => d.confidence >= (cameraConfig.minConfidence ?? 0.5))
        .sort((a, b) => b.confidence - a.confidence);
      const best = detections[0] || null;
      const box = Array.isArray(best?.box) ? best.box : null;
      const near = best && box && box.length === 4 && (
        (box[3] - box[1]) >= (nearConfig.boxHeightRatio ?? 0.22) ||
        ((box[2] - box[0]) * (box[3] - box[1])) >= (nearConfig.boxAreaRatio ?? 0.05)
      );
      const key = `${trainId}:${line}:${blockId}`;
      if (!near) {
        streaks.delete(key);
        return res.json({ ok: true, confirmed: false, degraded: false, stage: hazard.stage, detection: null });
      }

      const nearResult = state.applyCameraNear({
        line,
        blockId,
        trainId,
        species: best.label,
        confidence: best.confidence,
        bbox: best.box,
        capturedAt,
      });
      if (nearResult.ok && commands) commands.sync();

      const windowMs = (cameraConfig.confirmWindowSec ?? 2) * 1000;
      const previous = streaks.get(key);
      const streak = previous && now - previous.at <= windowMs ? previous.count + 1 : 1;
      streaks.set(key, { at: now, count: streak });

      if (streak >= (cameraConfig.confirmFrames ?? 2)) {
        state.applyCameraConfirmation({
          line,
          blockId,
          trainId,
          species: best.label,
          confidence: best.confidence,
          bbox: best.box,
          model: result.model,
          capturedAt: capturedAt || new Date().toISOString(),
        });
        fs.mkdirSync(evidenceDir, { recursive: true });
        const safeId = eventId.replace(/[^A-Za-z0-9._-]/g, '_');
        const file = path.join(evidenceDir, `${safeId}.jpg`);
        fs.writeFileSync(file, req.body);
        const files = fs.readdirSync(evidenceDir).map((f) => path.join(evidenceDir, f));
        if (files.length > 50) {
          files.sort((a, b) => fs.statSync(a).mtimeMs - fs.statSync(b).mtimeMs);
          for (const old of files.slice(0, files.length - 50)) fs.unlinkSync(old);
        }
        if (commands) commands.sync();
        audit.write({
          actor: 'camera',
          role: 'system',
          action: 'WILDLIFE_CONFIRMED',
          zone: hazard.zone,
          target: blockId,
          result: 'ACCEPTED',
          source: 'camera',
        });
        bus.event({ type: 'WILDLIFE_CONFIRMED', trainId, blockId, species: best.label, confidence: best.confidence });
        streaks.delete(key);
        return res.json({
          ok: true,
          confirmed: true,
          degraded: false,
          stage: 'CONFIRMED',
          confidence: best.confidence,
          species: best.label,
          qualified: true,
        });
      }

      bus.event({
        type: 'WILDLIFE_CAMERA_FRAME',
        trainId,
        blockId,
        confidence: best.confidence,
        species: best.label,
      });
      return res.json({
        ok: true,
        confirmed: false,
        degraded: false,
        stage: 'SUSPECTED',
        confidence: best.confidence,
        species: best.label,
        qualified: true,
      });
    },
  );

  return router;
}
