import { makeRng } from './rng.js';

const HISTORY_LIMIT = 10;

function defaultConfig(overrides = {}) {
  return {
    enabled: true,
    seed: 20261022,
    minGapSec: 60,
    maxGapSec: 180,
    stationWaitSec: 90,
    holdOffsetM: 80,
    minHoldSec: 6,
    maxHoldSec: 15,
    meetChance: 0.8,
    crossoverChance: 0.5,
    holdTimeoutSec: 25,
    ...overrides,
  };
}

export function makeMeetScheduler({ topology, trains, zones, routes, hasActiveHazard = () => false, config = {} }) {
  const cfg = defaultConfig(config.meets || {});
  const stations = topology.station?.blocks || {};
  let rng = makeRng(cfg.seed);

  let enabled = cfg.enabled !== false;
  let seedValue = Number(cfg.seed);
  let phase = 'IDLE';
  let tickCount = 0;
  let gapRemaining = sampleGap();
  let stationWaitRemaining = cfg.stationWaitSec;
  let holdRemaining = 0;
  let holdTimeoutRemaining = 0;
  let active = null;
  let pendingTrigger = false;
  let last = null;
  const history = [];

  function sampleGap() {
    return rng.nextRange(cfg.minGapSec, cfg.maxGapSec);
  }

  function toIdle() {
    phase = 'IDLE';
    active = null;
    pendingTrigger = false;
    gapRemaining = sampleGap();
  }

  function record(outcome) {
    if (!active) return;
    const entry = {
      tick: tickCount,
      holderId: active.holderId,
      otherId: active.otherId,
      crossed: Boolean(active.routeId),
      routeId: active.routeId || null,
      outcome,
    };
    last = { ...entry };
    history.push(entry);
    if (history.length > HISTORY_LIMIT) history.shift();
  }

  function blockRestricted(blockId) {
    const block = topology.blocks.find((b) => b.id === blockId);
    if (!block) return true;
    const zone = zones[block.zone];
    if (!zone) return true;
    return Boolean(
      hasActiveHazard(blockId) ||
      zone.wildlifeDetected ||
      zone.sensorHealthy === false ||
      zone.status === 'RECOVERY_REQUIRED',
    );
  }

  function releaseHold() {
    if (!active) return;
    const holder = trains.find((t) => t.id === active.holderId);
    if (holder) holder.commandedSpeedKmh = active.savedCommandedSpeed;
  }

  function prevBlockId(line, stationBlock) {
    const lineObj = topology.lines.find((l) => l.id === line);
    if (!lineObj) return null;
    const idx = lineObj.blocks.indexOf(stationBlock);
    if (idx < 0) return null;
    return lineObj.blocks[(idx - 1 + lineObj.blocks.length) % lineObj.blocks.length];
  }

  function inStationWindow(train) {
    const stationBlock = stations[train.line];
    if (!stationBlock) return false;
    if (train.block === stationBlock) return true;
    return train.block === prevBlockId(train.line, stationBlock);
  }

  function atStation(train) {
    const stationBlock = stations[train.line];
    return Boolean(stationBlock && train.block === stationBlock && train.offsetM <= cfg.holdOffsetM);
  }

  function crossoverFor(line) {
    const from = stations[line];
    if (!from) return null;
    return (topology.crossovers || []).find((route) => route.from === from) || null;
  }

  function beginHold(holder, other) {
    active = {
      holderId: holder.id,
      otherId: other.id,
      savedCommandedSpeed: holder.commandedSpeedKmh ?? null,
      holdRemainingSec: rng.nextRange(cfg.minHoldSec, cfg.maxHoldSec),
      crossover: rng.chance(cfg.crossoverChance),
      routeId: null,
      tick: tickCount,
    };
    holder.commandedSpeedKmh = 0;
    holdRemaining = active.holdRemainingSec;
    holdTimeoutRemaining = cfg.holdTimeoutSec;
    phase = 'HOLDING';
  }

  function tick(dtSec) {
    tickCount += 1;
    if (!enabled) return;

    if (phase === 'IDLE') {
      if (pendingTrigger) {
        pendingTrigger = false;
        stationWaitRemaining = cfg.stationWaitSec;
        phase = 'WAITING';
        return;
      }
      gapRemaining -= dtSec;
      if (gapRemaining <= 0) {
        stationWaitRemaining = cfg.stationWaitSec;
        phase = 'WAITING';
      }
      return;
    }

    if (phase === 'WAITING') {
      stationWaitRemaining -= dtSec;
      const candidates = trains.filter(atStation);
      if (candidates.length === 0) {
        if (stationWaitRemaining <= 0) {
          last = { tick: tickCount, outcome: 'SKIPPED' };
          toIdle();
        }
        return;
      }
      const holder = candidates.length > 1 ? (rng.chance(0.5) ? candidates[0] : candidates[1]) : candidates[0];
      const other = trains.find((t) => t.id !== holder.id);
      if (!other || !inStationWindow(other)) {
        if (stationWaitRemaining <= 0) {
          last = { tick: tickCount, outcome: 'SKIPPED' };
          toIdle();
        }
        return;
      }
      if (!rng.chance(cfg.meetChance)) {
        last = { tick: tickCount, outcome: 'SKIPPED' };
        toIdle();
        return;
      }
      beginHold(holder, other);
      return;
    }

    if (phase === 'HOLDING') {
      const holder = trains.find((t) => t.id === active.holderId);
      if (!holder) {
        releaseHold();
        record('SKIPPED');
        toIdle();
        return;
      }
      holdRemaining -= dtSec;
      holdTimeoutRemaining -= dtSec;

      if (active.crossover && !active.routeId) {
        const definition = crossoverFor(holder.line);
        if (definition) {
          const result = routes.requestRoute({ trainId: holder.id, routeId: definition.id });
          if (result.ok) active.routeId = definition.id;
        }
      }

      const restricted = blockRestricted(holder.block);
      if (holdRemaining <= 0 && !restricted && (!active.crossover || active.routeId)) {
        releaseHold();
        if (active.crossover) {
          phase = 'CROSSING';
        } else {
          record('HELD');
          toIdle();
        }
        return;
      }

      if (holdTimeoutRemaining <= 0 && !restricted) {
        releaseHold();
        record(active.crossover && !active.routeId ? 'SAFETY_HELD' : 'HELD');
        toIdle();
      }
      return;
    }

    if (phase === 'CROSSING') {
      const current = routes.activeRoute();
      if (!current || current.routeId !== active.routeId) {
        record('COMPLETED');
        toIdle();
      }
    }
  }

  function setEnabled(next) {
    enabled = Boolean(next);
    if (!enabled) {
      if (phase === 'HOLDING') releaseHold();
      active = null;
      phase = 'IDLE';
      pendingTrigger = false;
      gapRemaining = sampleGap();
    }
  }

  function setSeed(seed) {
    const numeric = Number(seed);
    if (!Number.isFinite(numeric)) return false;
    seedValue = numeric;
    rng = makeRng(seedValue);
    if (phase === 'IDLE') gapRemaining = sampleGap();
    return true;
  }

  function trigger() {
    if (!enabled || phase !== 'IDLE') return false;
    pendingTrigger = true;
    return true;
  }

  function snapshot() {
    return {
      enabled,
      seed: seedValue,
      phase,
      nextMeetInSec: phase === 'IDLE' ? Math.max(0, Math.round(gapRemaining * 10) / 10) : 0,
      config: { meetChance: cfg.meetChance, crossoverChance: cfg.crossoverChance },
      active: active
        ? {
            tick: active.tick,
            holderId: active.holderId,
            otherId: active.otherId,
            holdRemainingSec: Math.max(0, Math.round(holdRemaining * 10) / 10),
            crossover: active.crossover,
            routeId: active.routeId,
          }
        : null,
      last: last ? { ...last } : null,
      history: history.map((entry) => ({ ...entry })),
    };
  }

  return { tick, snapshot, setEnabled, setSeed, trigger };
}
