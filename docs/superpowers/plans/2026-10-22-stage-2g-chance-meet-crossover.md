# Stage 2G — Chance-Based Meet Crossover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed, client-scripted meet with a backend-authoritative, seeded, randomised meet scheduler that holds one train at the platform, optionally crosses it via a station crossover through the existing interlock, and exposes live meet state to the Godot HUD and web dashboard.

**Architecture:** A new `backend/src/meets.js` state machine runs inside `state.tick`, holding trains via `commandedSpeedKmh = 0` and requesting crossovers only through `routes.requestRoute()`. A seeded mulberry32 PRNG (`backend/src/rng.js`) makes every decision reproducible. Meet state is added to the authoritative `railway/state` snapshot; Godot and the web dashboard render it without new motion logic.

**Tech Stack:** Node.js ESM backend (`node --test`), MQTT bridge, Godot 4.7 GDScript HUD, React 18 + TypeScript + Vite dashboard.

**Spec:** [`docs/superpowers/specs/2026-10-22-stage-2g-chance-meet-crossover-design.md`](../specs/2026-10-22-stage-2g-chance-meet-crossover-design.md)

---

## Global Constraints

- Educational simulation only; nothing here is certified railway signalling or safety equipment.
- Backend owns authoritative train motion, holds, blocks, and route grants. Godot only renders.
- Holds are `train.commandedSpeedKmh = 0`; the previous value is saved and restored on release.
- Crossovers are requested only through `routes.requestRoute` (occupancy, hazard, restrictive-zone checks are never bypassed).
- A hold is never released while the train's block has an active hazard, an unhealthy sensor zone, or `RECOVERY_REQUIRED`.
- All randomness comes from one seeded PRNG; no `Math.random()` in scheduler decisions. Fixed seed + fixed tick sequence ⇒ identical meet history.
- `MEETS_ENABLED=0` or `config.meets.enabled = false` must reproduce pre-2G fixed-loop behaviour exactly.
- Keep all existing suites green: Godot 33/33, backend 90/90, ESP32 native 15/15, web build.
- Godot tests run headless via `/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64`; full suite via `bash godot/tests/run_tests.sh`.

---

## File Structure

- Create: `backend/src/rng.js` — seeded mulberry32 PRNG helper (`makeRng`).
- Create: `backend/src/meets.js` — meet scheduler state machine (`makeMeetScheduler`).
- Create: `backend/test/rng.test.js` — PRNG determinism tests.
- Create: `backend/test/meets.test.js` — scheduler unit + state integration tests.
- Modify: `backend/src/config.js` — `meets` config defaults and validation.
- Modify: `backend/src/state.js` — instantiate the scheduler, tick it, expose `state.meets`, add `meetControl`.
- Modify: `backend/src/validate.js` — `validateMeet`.
- Modify: `backend/src/routes/control.js` — `POST /api/meet`.
- Modify: `backend/test/config.test.js` — meets defaults assertions.
- Modify: `backend/test/validate.test.js` — `validateMeet` coverage.
- Modify: `backend/test/control_routes.test.js` — `/api/meet` auth/RBAC/dedupe/audit.
- Modify: `godot/src/twin_hud.gd` — subscribe to `railway/state`, display meet line.
- Create: `godot/tests/test_meet_hud.gd` — HUD meet rendering.
- Create: `godot/tests/capture_meet.gd` — station meet evidence capture.
- Modify: `web/src/App.tsx` — meet card.
- Modify: `web/src/style.css` — meet card styling.
- Modify: `docs/porting/acceptance.md` — Stage 2G verification section.
- Modify: `docs/superpowers/plans/2026-10-22-stage-2f-wildlife-sensing.md` — remove duplicated trailing unchecked steps.

---

### Task 1: Seeded PRNG

**Files:**
- Create: `backend/src/rng.js`
- Test: `backend/test/rng.test.js`

**Interfaces:**
- Consumes: nothing.
- Produces: `makeRng(seed: number) -> { nextFloat(): number, nextRange(min: number, max: number): number, chance(p: number): boolean }`.

- [x] **Step 1: Write the failing test**

Create `backend/test/rng.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeRng } from '../src/rng.js';

test('same seed reproduces the same sequence', () => {
  const a = makeRng(20261022);
  const b = makeRng(20261022);
  const seqA = Array.from({ length: 20 }, () => a.nextFloat());
  const seqB = Array.from({ length: 20 }, () => b.nextFloat());
  assert.deepEqual(seqA, seqB);
});

test('different seeds produce different sequences', () => {
  const a = makeRng(1);
  const b = makeRng(2);
  const seqA = Array.from({ length: 10 }, () => a.nextFloat());
  const seqB = Array.from({ length: 10 }, () => b.nextFloat());
  assert.notDeepEqual(seqA, seqB);
});

test('values stay inside their ranges', () => {
  const rng = makeRng(7);
  for (let i = 0; i < 100; i++) {
    const v = rng.nextFloat();
    assert.ok(v >= 0 && v < 1);
    const r = rng.nextRange(5, 9);
    assert.ok(r >= 5 && r < 9);
  }
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/rng.test.js`
Expected: FAIL — cannot find module `../src/rng.js`.

- [x] **Step 3: Write minimal implementation**

Create `backend/src/rng.js`:

```js
export function mulberry32(seed) {
  let a = seed >>> 0;
  return function next() {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function makeRng(seed) {
  const next = mulberry32(Number(seed));
  return {
    nextFloat: () => next(),
    nextRange: (min, max) => min + next() * (max - min),
    chance: (p) => next() < p,
  };
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/rng.test.js`
Expected: PASS (3 tests).

- [x] **Step 5: Commit**

```bash
git add backend/src/rng.js backend/test/rng.test.js
git commit -m "feat(backend): seeded prng for reproducible meet scheduling"
```

---

### Task 2: Meet Scheduler State Machine

**Files:**
- Create: `backend/src/meets.js`
- Test: `backend/test/meets.test.js`

**Interfaces:**
- Consumes: `makeRng` from Task 1; `topology`, `trains`, `zones`, `routes`, `hasActiveHazard` from the caller.
- Produces: `makeMeetScheduler({ topology, trains, zones, routes, hasActiveHazard, config }) -> { tick(dtSec), snapshot(), setEnabled(bool), setSeed(number), trigger() }`.

- [x] **Step 1: Write the failing tests**

Create `backend/test/meets.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeMeetScheduler } from '../src/meets.js';

function makeWorld(overrides = {}) {
  const lineBlocks = (line) => Array.from({ length: 5 }, (_, i) => `${line}-B${i}`);
  const topology = {
    lines: [
      { id: 'UP', blocks: lineBlocks('UP') },
      { id: 'DOWN', blocks: lineBlocks('DOWN') },
    ],
    blocks: ['UP', 'DOWN'].flatMap((line) =>
      lineBlocks(line).map((id, index) => ({ id, line, index, zone: index < 3 ? 'zone1' : 'zone2' }))),
    station: { id: 'station', blocks: { UP: 'UP-B2', DOWN: 'DOWN-B2' } },
    crossovers: [
      { id: 'X-UP-DOWN', from: 'UP-B2', to: 'DOWN-B2' },
      { id: 'X-DOWN-UP', from: 'DOWN-B2', to: 'UP-B2' },
    ],
  };
  const zones = {
    zone1: { wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' },
    zone2: { wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' },
  };
  const trains = overrides.trains || [
    { id: 'T1', line: 'UP', block: 'UP-B2', offsetM: 10, speedKmh: 0, commandedSpeedKmh: null },
    { id: 'T3', line: 'DOWN', block: 'DOWN-B1', offsetM: 100, speedKmh: 48, commandedSpeedKmh: null },
  ];
  const routeCalls = [];
  let activeRoute = null;
  let hazardBlock = overrides.hazardBlock || null;
  const routes = {
    requestRoute({ trainId, routeId }) {
      routeCalls.push({ trainId, routeId });
      if (overrides.rejectRoutes) return { ok: false, reason: 'rejected' };
      const definition = topology.crossovers.find((r) => r.id === routeId);
      const train = trains.find((t) => t.id === trainId);
      if (!definition || !train || train.block !== definition.from) {
        return { ok: false, reason: 'not at from block' };
      }
      if (trains.some((t) => t.id !== trainId && t.block === definition.to)) {
        return { ok: false, reason: 'destination occupied' };
      }
      activeRoute = { routeId, trainId, from: definition.from, to: definition.to };
      train.line = definition.to.split('-')[0];
      train.block = definition.to;
      train.offsetM = 0;
      return { ok: true, route: { ...activeRoute } };
    },
    activeRoute: () => (activeRoute ? { ...activeRoute } : null),
    clear: () => { activeRoute = null; },
  };
  const meets = {
    enabled: true,
    seed: 42,
    minGapSec: 0.5,
    maxGapSec: 0.5,
    stationWaitSec: 10,
    holdOffsetM: 80,
    minHoldSec: 1,
    maxHoldSec: 2,
    meetChance: 1,
    crossoverChance: 0,
    holdTimeoutSec: 5,
    ...overrides.meets,
  };
  const scheduler = makeMeetScheduler({
    topology,
    trains,
    zones,
    routes,
    config: { meets },
    hasActiveHazard: (id) => hazardBlock === id,
  });
  return {
    topology,
    zones,
    trains,
    routes,
    routeCalls,
    scheduler,
    __clearHazard: () => { hazardBlock = null; },
  };
}

test('a meet holds one train at the station while the other moves', () => {
  const w = makeWorld({ meets: { crossoverChance: 0 } });
  w.scheduler.tick(0.5);
  w.scheduler.tick(0.5);
  let snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'HOLDING');
  const holder = w.trains.find((t) => t.id === snap.active.holderId);
  const other = w.trains.find((t) => t.id !== holder.id);
  assert.equal(holder.commandedSpeedKmh, 0);
  assert.equal(other.commandedSpeedKmh, null);

  w.scheduler.tick(2.1);
  snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'IDLE');
  assert.equal(holder.commandedSpeedKmh, null);
  assert.equal(snap.last.outcome, 'HELD');
});

test('crossover meets request the valid station route and complete after release', () => {
  const w = makeWorld({ meets: { crossoverChance: 1, minHoldSec: 0.5, maxHoldSec: 0.5 } });
  w.scheduler.tick(0.5);
  w.scheduler.tick(0.5);
  const holderId = w.scheduler.snapshot().active.holderId;
  w.scheduler.tick(0.1);
  let snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'HOLDING');
  assert.equal(snap.active.routeId, 'X-UP-DOWN');
  assert.ok(w.routeCalls.some((call) => call.routeId === 'X-UP-DOWN'));

  w.scheduler.tick(0.6);
  snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'CROSSING');
  const holder = w.trains.find((t) => t.id === holderId);
  assert.equal(holder.line, 'DOWN');

  w.routes.clear();
  w.scheduler.tick(0.1);
  snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'IDLE');
  assert.equal(snap.last.outcome, 'COMPLETED');
});

test('a hold is not released while the block has an active hazard', () => {
  const w = makeWorld({ meets: { crossoverChance: 0, minHoldSec: 0.5, maxHoldSec: 0.5 }, hazardBlock: 'UP-B2' });
  w.scheduler.tick(0.5);
  w.scheduler.tick(0.5);
  w.scheduler.tick(2.0);
  let snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'HOLDING');
  const holder = w.trains.find((t) => t.id === snap.active.holderId);
  assert.equal(holder.commandedSpeedKmh, 0);

  w.__clearHazard();
  w.scheduler.tick(0.5);
  snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'IDLE');
  assert.equal(holder.commandedSpeedKmh, null);
});

test('skips a crossover when the interlock rejects the route', () => {
  const w = makeWorld({ rejectRoutes: true, meets: { crossoverChance: 1, holdTimeoutSec: 1.0 } });
  let guard = 0;
  while (!w.scheduler.snapshot().last && guard < 20) {
    w.scheduler.tick(0.5);
    guard += 1;
  }
  const snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'IDLE');
  assert.equal(snap.last.outcome, 'SAFETY_HELD');
  assert.equal(w.routes.activeRoute(), null);
});

test('same seed reproduces the same meet history; a different seed changes it', () => {
  const run = (seed) => {
    const w = makeWorld({
      meets: {
        seed,
        minGapSec: 0.2,
        maxGapSec: 0.2,
        minHoldSec: 0.5,
        maxHoldSec: 1.5,
        meetChance: 0.6,
        crossoverChance: 0.5,
        holdTimeoutSec: 5,
      },
    });
    for (let i = 0; i < 240; i++) {
      w.scheduler.tick(0.2);
      if (w.routes.activeRoute()) w.routes.clear();
    }
    return w.scheduler.snapshot().history;
  };
  assert.deepEqual(run(123), run(123));
  assert.notDeepEqual(run(123), run(124));
});

test('disabled meets never hold or grant routes', () => {
  const w = makeWorld({ meets: { enabled: false } });
  for (let i = 0; i < 20; i++) w.scheduler.tick(0.5);
  const snap = w.scheduler.snapshot();
  assert.equal(snap.phase, 'IDLE');
  assert.equal(snap.last, null);
  assert.equal(w.trains[0].commandedSpeedKmh, null);
  assert.equal(w.routeCalls.length, 0);
});

test('trigger starts the next meet at the next station window', () => {
  const w = makeWorld({ meets: { minGapSec: 999, maxGapSec: 999 } });
  w.scheduler.tick(0.5);
  assert.equal(w.scheduler.snapshot().phase, 'IDLE');
  assert.equal(w.scheduler.trigger(), true);
  w.scheduler.tick(0.5);
  assert.equal(w.scheduler.snapshot().phase, 'WAITING');
  w.scheduler.tick(0.5);
  assert.equal(w.scheduler.snapshot().phase, 'HOLDING');
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/meets.test.js`
Expected: FAIL — cannot find module `../src/meets.js`.

- [x] **Step 3: Write the scheduler implementation**

Create `backend/src/meets.js`:

```js
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
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/meets.test.js`
Expected: PASS (7 tests).

- [x] **Step 5: Commit**

```bash
git add backend/src/meets.js backend/test/meets.test.js
git commit -m "feat(backend): seeded meet scheduler with holds and safe crossovers"
```

---

### Task 3: Wire the Scheduler into State and Config

**Files:**
- Modify: `backend/src/config.js`
- Modify: `backend/src/state.js`
- Modify: `backend/test/config.test.js`
- Modify: `backend/test/meets.test.js` (integration section)

**Interfaces:**
- Consumes: `makeMeetScheduler` from Task 2.
- Produces: `state.snapshot().meets` (object described in the spec); `state.meetControl({ enabled?, seed?, trigger? }) -> { ok, meets? , reason? }`.

- [x] **Step 1: Add failing config and integration tests**

Append to `backend/test/config.test.js`:

```js
test('config exposes meet scheduler defaults', () => {
  assert.equal(typeof config.meets, 'object');
  assert.equal(config.meets.enabled, true);
  assert.equal(config.meets.seed, 20261022);
  assert.ok(config.meets.minGapSec <= config.meets.maxGapSec);
  assert.ok(config.meets.meetChance >= 0 && config.meets.meetChance <= 1);
  assert.ok(config.meets.crossoverChance >= 0 && config.meets.crossoverChance <= 1);
});
```

Append to `backend/test/meets.test.js`:

```js
import { config } from '../src/config.js';
import { makeState } from '../src/state.js';

test('state snapshot exposes live meet state and holds a train', () => {
  const cfg = {
    ...config,
    meets: {
      ...config.meets,
      enabled: true,
      seed: 7,
      minGapSec: 0.1,
      maxGapSec: 0.1,
      stationWaitSec: 120,
      minHoldSec: 1,
      maxHoldSec: 2,
      meetChance: 1,
      crossoverChance: 0.5,
    },
  };
  const state = makeState({ config: cfg });
  assert.ok(state.snapshot().meets, 'meets snapshot present');
  assert.equal(state.snapshot().meets.enabled, true);
  let meetObserved = false;
  for (let i = 0; i < 300; i++) {
    state.tick(0.5);
    const snap = state.snapshot();
    if (snap.meets.active || snap.meets.last) meetObserved = true;
    assert.notEqual(
      `${snap.trains[0].line}:${snap.trains[0].block}`,
      `${snap.trains[1].line}:${snap.trains[1].block}`,
      'no two trains in the same line and block',
    );
  }
  assert.ok(meetObserved, 'a meet occurred within 150 simulated seconds');
});

test('disabled meets leave the fixed-loop simulation unchanged', () => {
  const cfg = { ...config, meets: { ...config.meets, enabled: false } };
  const state = makeState({ config: cfg });
  for (let i = 0; i < 20; i++) state.tick(0.5);
  const snap = state.snapshot();
  assert.equal(snap.meets.enabled, false);
  assert.equal(snap.meets.phase, 'IDLE');
  assert.equal(snap.meets.last, null);
  assert.ok(snap.trains.some((t) => t.targetSpeedKmh > 0));
});
```

- [x] **Step 2: Run tests to verify they fail**

Run: `cd backend && node --test test/config.test.js test/meets.test.js`
Expected: FAIL — `config.meets` undefined; `state.snapshot().meets` undefined.

- [x] **Step 3: Implement config + state wiring**

In `backend/src/config.js`, add after `simulation`:

```js
  meets: {
    enabled: process.env.MEETS_ENABLED !== '0',
    seed: Number(process.env.MEET_SEED || 20261022),
    minGapSec: 60,
    maxGapSec: 180,
    stationWaitSec: 90,
    holdOffsetM: 80,
    minHoldSec: 6,
    maxHoldSec: 15,
    meetChance: 0.8,
    crossoverChance: 0.5,
    holdTimeoutSec: 25,
  },
```

In `validateConfig(c)`, before the final error throw, add:

```js
  const meets = c.meets || {};
  if (meets.minGapSec != null && meets.maxGapSec != null && !(meets.minGapSec <= meets.maxGapSec)) {
    errors.push('meets gap range invalid');
  }
  for (const key of ['meetChance', 'crossoverChance']) {
    if (meets[key] != null && (meets[key] < 0 || meets[key] > 1)) errors.push(`meets.${key} must be 0..1`);
  }
  if (meets.holdOffsetM != null && meets.holdOffsetM < 0) errors.push('meets.holdOffsetM must be >= 0');
```

In `backend/src/state.js`:

1. Import the scheduler:

```js
import { makeMeetScheduler } from './meets.js';
```

2. Declare `let meets = null;` next to `let routes = null;`.

3. After `routes = makeRoutes({...});` add:

```js
    meets = makeMeetScheduler({
      topology: topo,
      trains,
      zones,
      routes,
      hasActiveHazard: (id) => Boolean(blockHazards[id]?.active),
      config,
    });
```

4. In `fleetSnapshot()` return object, add after `routes: ...`:

```js
      meets: meets ? meets.snapshot() : null,
```

5. In `tick(dtSec)`, run the scheduler before `routes.tick()`:

```js
    if (meets) meets.tick(dtSec);
    routes.tick();
```

6. Add `meetControl` before the returned object and export it:

```js
  function meetControl({ enabled, seed, trigger } = {}) {
    if (!meets) return { ok: false, reason: 'meets unavailable' };
    if (typeof enabled === 'boolean') meets.setEnabled(enabled);
    if (seed !== undefined) {
      if (!meets.setSeed(seed)) return { ok: false, reason: 'invalid seed' };
    }
    if (trigger === true && !meets.trigger()) return { ok: false, reason: 'meet not triggerable in current phase' };
    return { ok: true, meets: meets.snapshot() };
  }
```

7. Add `meetControl` to the returned state object:

```js
    requestRoute, meetControl, tick, getTickCount: () => tickCount,
```

- [x] **Step 4: Run tests to verify they pass**

Run: `cd backend && node --test test/config.test.js test/meets.test.js`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add backend/src/config.js backend/src/state.js backend/test/config.test.js backend/test/meets.test.js
git commit -m "feat(backend): expose seeded meet state and control"
```

---

### Task 4: REST Control for the Meet Scheduler

**Files:**
- Modify: `backend/src/validate.js`
- Modify: `backend/src/routes/control.js`
- Modify: `backend/test/validate.test.js`
- Modify: `backend/test/control_routes.test.js`

**Interfaces:**
- Consumes: `state.meetControl` from Task 3.
- Produces: `POST /api/meet` accepting `{ request_id, enabled?, seed?, trigger? }` with `route:set` permission.

- [x] **Step 1: Write failing tests**

Append to `backend/test/validate.test.js`:

```js
import { validateMeet } from '../src/validate.js';

test('validateMeet accepts toggles, seeds and triggers', () => {
  assert.equal(validateMeet({ request_id: 'm1', enabled: true }).ok, true);
  assert.equal(validateMeet({ request_id: 'm2', seed: 42 }).ok, true);
  assert.equal(validateMeet({ request_id: 'm3', trigger: true }).ok, true);
});

test('validateMeet rejects missing ids and bad types', () => {
  assert.equal(validateMeet({ enabled: true }).ok, false);
  assert.equal(validateMeet({ request_id: 'm4', enabled: 'yes' }).ok, false);
  assert.equal(validateMeet({ request_id: 'm5', seed: 'abc' }).ok, false);
  assert.equal(validateMeet({ request_id: 'm6', trigger: 1 }).ok, false);
});
```

Append to `backend/test/control_routes.test.js`:

```js
test('meet control enforces auth, rbac, validation, replay and audit', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const body = { request_id: 'meet-1', enabled: true, seed: 99 };
    const anon = await fetch(`${url}/api/meet`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    assert.equal(anon.status, 401);

    const viewer = await tokenFor(url, 'viewer');
    const forbidden = await fetch(`${url}/api/meet`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${viewer}` }, body: JSON.stringify(body) });
    assert.equal(forbidden.status, 403);

    const operator = await tokenFor(url, 'operator');
    const ok = await fetch(`${url}/api/meet`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` }, body: JSON.stringify(body) });
    assert.equal(ok.status, 200);
    const okBody = await ok.json();
    assert.equal(okBody.state.meets.seed, 99);
    assert.equal(okBody.state.meets.enabled, true);

    const dup = await fetch(`${url}/api/meet`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` }, body: JSON.stringify(body) });
    assert.equal(dup.status, 400);

    const bad = await fetch(`${url}/api/meet`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` }, body: JSON.stringify({ request_id: 'meet-2', seed: 'abc' }) });
    assert.equal(bad.status, 400);

    assert.ok(deps.audit.list().some((row) => row.action === 'MEET' && row.result === 'ACCEPTED'));
  });
});
```

- [x] **Step 2: Run tests to verify they fail**

Run: `cd backend && node --test test/validate.test.js test/control_routes.test.js`
Expected: FAIL — `validateMeet` is not exported; `/api/meet` returns 404.

- [x] **Step 3: Implement validation and route**

Append to `backend/src/validate.js`:

```js
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
```

In `backend/src/routes/control.js`, add `validateMeet` to the import:

```js
import { validateCommand, validateMeet, validateRoute, validateSpeed } from '../validate.js';
```

Add this route before `return router;`:

```js
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
```

- [x] **Step 4: Run tests to verify they pass**

Run: `cd backend && node --test test/validate.test.js test/control_routes.test.js`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add backend/src/validate.js backend/src/routes/control.js backend/test/validate.test.js backend/test/control_routes.test.js
git commit -m "feat(backend): operator meet scheduler control endpoint"
```

---

### Task 5: Godot HUD Meet Line

**Files:**
- Modify: `godot/src/twin_hud.gd`
- Create: `godot/tests/test_meet_hud.gd`

**Interfaces:**
- Consumes: `railway/state` snapshots containing `meets` from Task 3.
- Produces: `TwinHUD.apply_state(state: Dictionary) -> void`; metrics text containing `MEET`/`meet in`.

- [x] **Step 1: Write the failing test**

Create `godot/tests/test_meet_hud.gd`:

```gdscript
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	var bridge := scene.get_node("MQTTBridge") as MQTTBridge
	bridge.connect_on_ready = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var hud := scene.get_node_or_null("HUD") as TwinHUD
	a.ok(hud != null, "HUD exists in scene")

	if hud:
		hud.apply_state({
			"meets": {
				"enabled": true,
				"seed": 20261022,
				"phase": "HOLDING",
				"nextMeetInSec": 0,
				"active": {
					"holderId": "T3",
					"otherId": "T1",
					"crossover": true,
					"routeId": "X-DOWN-UP"
				}
			}
		})
		var metrics := (hud.get("_metrics") as Label).text
		a.ok(metrics.contains("MEET"), "HUD shows meet phase")
		a.ok(metrics.contains("T3"), "HUD shows the holding train")
		a.ok(metrics.contains("X-DOWN-UP"), "HUD shows the crossover route")

		hud.apply_state({
			"meets": {
				"enabled": true,
				"seed": 20261022,
				"phase": "IDLE",
				"nextMeetInSec": 42.0,
				"active": null
			}
		})
		metrics = (hud.get("_metrics") as Label).text
		a.ok(metrics.contains("meet in 42s"), "HUD counts down to the next meet")

		hud.apply_state({})
		a.ok(true, "HUD tolerates a snapshot without meets")

	scene.queue_free()
	await process_frame
	quit(a.report("test_meet_hud"))
```

- [x] **Step 2: Run test to verify it fails**

Run: `timeout 90 /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_meet_hud.gd 2>&1 | grep -E "^(PASS|FAIL)"`
Expected: FAIL — `apply_state` missing on `TwinHUD`.

- [x] **Step 3: Implement HUD meet rendering**

In `godot/src/twin_hud.gd`:

1. Add a member near `var selected_train_id := "T1"`:

```gdscript
var _meet: Dictionary = {}
```

2. Connect the bridge in `_ready()` after creating the labels:

```gdscript
	var bridge := get_node_or_null(bridge_path) as MQTTBridge
	if bridge:
		bridge.message_received.connect(_on_message)
```

3. Add these functions before `refresh()`:

```gdscript
func _on_message(topic: String, payload: Dictionary) -> void:
	if topic == "railway/state":
		apply_state(payload)


func apply_state(state: Dictionary) -> void:
	var meet_var: Variant = state.get("meets")
	if meet_var is Dictionary:
		_meet = meet_var
	refresh()


func _meet_text() -> String:
	if _meet.is_empty() or not bool(_meet.get("enabled", false)):
		return ""
	var phase := str(_meet.get("phase", "IDLE"))
	if phase == "IDLE":
		var seconds := int(ceil(float(_meet.get("nextMeetInSec", 0.0))))
		return "meet in %ds" % seconds
	var active_var: Variant = _meet.get("active")
	if active_var is Dictionary and not active_var.is_empty():
		var holder := str(active_var.get("holderId", "?"))
		var route := str(active_var.get("routeId", ""))
		var extra := ""
		if not route.is_empty():
			extra = " via %s" % route
		return "MEET %s %s%s" % [phase, holder, extra]
	return "MEET %s" % phase
```

4. Append the meet text to the metrics line. Replace the two `_metrics.text` assignments with:

```gdscript
	var meet_text := _meet_text()
	var meet_suffix := "" if meet_text.is_empty() else "   %s" % meet_text
	if fleet and fleet.train_count() > 1:
		_metrics.text = "train %s [%s] speed %.1f km/h (target %.1f, limit %.1f)   camera: %s%s" % [selected_train_id, current_block, speed, target, limit, mode, meet_suffix]
	else:
		_metrics.text = "speed %.1f km/h (target %.1f, limit %.1f)   camera: %s%s" % [speed, target, limit, mode, meet_suffix]
```

- [x] **Step 4: Run tests to verify they pass**

Run: `timeout 90 /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_meet_hud.gd 2>&1 | grep -E "^(PASS|FAIL)"`
Expected: `PASS test_meet_hud`.

- [x] **Step 5: Commit**

```bash
git add godot/src/twin_hud.gd godot/tests/test_meet_hud.gd
git commit -m "feat(godot): render live meet scheduler state in the HUD"
```

---

### Task 6: Web Dashboard Meet Card

**Files:**
- Modify: `web/src/App.tsx`
- Modify: `web/src/style.css`

**Interfaces:**
- Consumes: `state.meets` from the backend snapshot.
- Produces: a rendered meet card; `npm --prefix web run build` stays clean.

- [x] **Step 1: Add the type and card**

In `web/src/App.tsx`, add above `type State`:

```ts
type Meet = {
  enabled: boolean;
  seed: number;
  phase: string;
  nextMeetInSec: number;
  active?: {
    holderId?: string;
    otherId?: string;
    crossover?: boolean;
    routeId?: string | null;
  } | null;
  last?: {
    outcome?: string;
    holderId?: string;
    routeId?: string | null;
  } | null;
};
```

Add to `type State`:

```ts
  meets?: Meet | null;
```

After the `routes` computation near `const activeRoute = state.routes?.activeRoute;`, add:

```ts
  const meet = state.meets;
```

Insert this section immediately after the fleet-grid `</section>`:

```tsx
      {meet && (
        <section className="panel meet-panel">
          <div className="panel-head">
            <div>
              <div className="eyebrow">RANDOMISED MEETS</div>
              <h3>Chance-Based Crossover Scheduler</h3>
            </div>
            <ArrowRightLeft size={19} />
          </div>
          <div className="meet-grid">
            <div><small>Phase</small><b>{meet.enabled ? meet.phase : 'DISABLED'}</b></div>
            <div><small>Next meet</small><b>{meet.phase === 'IDLE' ? `${Math.ceil(meet.nextMeetInSec)} s` : 'ACTIVE'}</b></div>
            <div><small>Holder</small><b>{meet.active?.holderId || '—'}</b></div>
            <div><small>Route</small><b>{meet.active?.routeId || meet.last?.routeId || '—'}</b></div>
            <div><small>Seed</small><b>{meet.seed}</b></div>
            <div><small>Last outcome</small><b>{meet.last?.outcome || '—'}</b></div>
          </div>
        </section>
      )}
```

- [x] **Step 2: Add styling**

Append to `web/src/style.css`:

```css
.meet-panel { margin-top: 18px; }
.meet-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 12px;
}
.meet-grid div {
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 10px;
  padding: 10px 12px;
}
.meet-grid small {
  display: block;
  color: var(--muted, #8fa3b3);
  font-size: 11px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  margin-bottom: 4px;
}
.meet-grid b { font-size: 15px; }
```

- [x] **Step 3: Verify the build**

Run: `npm --prefix web run build`
Expected: `✓ built` with no TypeScript errors.

- [x] **Step 4: Commit**

```bash
git add web/src/App.tsx web/src/style.css
git commit -m "feat(web): show randomised meet scheduler status"
```

---

### Task 7: Evidence Capture, Docs, and Full Verification

**Files:**
- Create: `godot/tests/capture_meet.gd`
- Modify: `docs/porting/acceptance.md`
- Modify: `docs/superpowers/plans/2026-10-22-stage-2f-wildlife-sensing.md`
- Modify: `docs/superpowers/plans/2026-10-22-stage-2g-chance-meet-crossover.md` (tick checkboxes at the end)

**Interfaces:**
- Consumes: HUD `apply_state` (Task 5), fleet rendering (existing).
- Produces: `/tmp/opencode/meet_randomized.png`; Stage 2G acceptance row.

- [x] **Step 1: Create the capture script**

Create `godot/tests/capture_meet.gd`:

```gdscript
extends SceneTree

## Run: xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 \
##        --path godot --resolution 1280x720 --rendering-method gl_compatibility \
##        --script res://tests/capture_meet.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	for frame in 12:
		await process_frame

	var fleet := scene.get_node_or_null("FleetController") as FleetController
	if fleet:
		fleet.apply_state({
			"trains": [
				{"id": "T1", "line": "UP", "block": "UP-B2", "offsetM": 20.0, "speedKmh": 0.0, "targetSpeedKmh": 0.0},
				{"id": "T3", "line": "DOWN", "block": "DOWN-B2", "offsetM": 30.0, "speedKmh": 45.0, "targetSpeedKmh": 45.0}
			]
		})

	var hud := scene.get_node_or_null("HUD") as TwinHUD
	if hud:
		hud.apply_state({
			"meets": {
				"enabled": true,
				"seed": 20261022,
				"phase": "HOLDING",
				"nextMeetInSec": 0,
				"active": {
					"holderId": "T1",
					"otherId": "T3",
					"holdRemainingSec": 8.0,
					"crossover": true,
					"routeId": "X-UP-DOWN"
				},
				"last": null
			}
		})

	var camera := Camera3D.new()
	camera.fov = 55.0
	camera.far = 2000.0
	scene.add_child(camera)
	camera.global_position = Vector3(78.0, 16.0, -252.0)
	camera.look_at(Vector3(30.0, 1.0, -231.0), Vector3.UP)
	camera.make_current()
	for frame in 4:
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/opencode/meet_randomized.png")
	quit()
```

- [x] **Step 2: Capture and inspect**

Run: `timeout 180 xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --path godot --resolution 1280x720 --rendering-method gl_compatibility --script res://tests/capture_meet.gd`
Expected: `/tmp/opencode/meet_randomized.png` exists, non-zero, shows both trains at the island platform and the HUD meet line.

- [x] **Step 3: Update the acceptance doc**

Insert a new section in `docs/porting/acceptance.md` before `## Manual demo`:

```markdown
## Stage 2G chance-based meet crossover verification (2026-10-22)

Stage 2G replaces the fixed scripted meet with a backend-authoritative seeded
meet scheduler. Holds use `commandedSpeedKmh = 0` on the authoritative train;
crossovers are granted only through `routes.requestRoute` (occupancy, hazard,
and restrictive-zone checks unchanged).

| Item | Evidence |
|---|---|
| Seeded PRNG | `test/rng.test.js` PASS: same seed reproduces the sequence, different seeds diverge, values stay in range |
| Meet scheduler | `test/meets.test.js` PASS: hold while the other train moves, hold release only after expiry/hazard clear, disabled mode inert, trigger arms the next window |
| Crossover safety | `test/meets.test.js` PASS: valid station route only, interlock rejections retried then skipped as `SAFETY_HELD`, completion after route release |
| Reproducibility | `test/meets.test.js` PASS: identical history for the same seed, different history for another seed |
| REST control | `test/control_routes.test.js` PASS: `/api/meet` auth/RBAC/validation/replay/audit; seed applied to the live snapshot |
| Godot HUD | `test_meet_hud.gd` PASS: phase, holder, route and next-meet countdown; absent `meets` tolerated |
| Web dashboard | `web/src/App.tsx` meet card builds cleanly |
| Capture | `/tmp/opencode/meet_randomized.png` (station meet with two trains and active crossover) |
```

- [x] **Step 4: Run the full verification**

```bash
timeout 500 bash godot/tests/run_tests.sh 2>&1 | tee /tmp/opencode/suite_2g.log | grep -cE "^PASS"
grep -cE "^FAIL" /tmp/opencode/suite_2g.log
docker run -d --rm --name rdt-test-mqtt -p 127.0.0.1:1884:1883 -v "$PWD/mosquitto:/mosquitto/config:ro" eclipse-mosquitto:2
MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test
docker stop rdt-test-mqtt
/home/kathir/.local/bin/pio test -e native --project-dir esp32
npm --prefix web run build
```

Expected: Godot PASS count increases by one (34), FAIL 0; backend all pass (count grows by the new tests); ESP32 15/15; web build clean.

- [x] **Step 5: Clean up the duplicated 2F plan tail**

In `docs/superpowers/plans/2026-10-22-stage-2f-wildlife-sensing.md`, delete the two duplicated trailing lines:

```markdown
- [x] Update `docs/porting/acceptance.md` with Stage 2F verification gates.
- [x] Conventional Commit: `docs(2f): complete stage 2F verification and delivery record`.
```

(They duplicate already-checked Task 7 items immediately above.)

- [x] **Step 6: Commit**

```bash
git add godot/tests/capture_meet.gd docs/porting/acceptance.md docs/superpowers/plans/2026-10-22-stage-2f-wildlife-sensing.md
git commit -m "docs(2g): record randomized meet verification and evidence"
```

- [x] **Step 7: Tick the plan checkboxes**

Replace every `- [ ]` with `- [x]` in this plan file, then:

```bash
git add docs/superpowers/plans/2026-10-22-stage-2g-chance-meet-crossover.md
git commit -m "docs(2g): tick 2g plan checkboxes"
```

---

## Stage 2G Exit Gate

- `backend/test/rng.test.js` and `backend/test/meets.test.js` pass.
- `/api/meet` covered by auth/RBAC/validation/replay/audit tests.
- Godot suite passes with the new `test_meet_hud.gd` (34 suites, 0 failures).
- Web dashboard builds; meet card renders from `state.meets`.
- `/tmp/opencode/meet_randomized.png` shows a station meet with the HUD meet line.
- Disabled mode (`MEETS_ENABLED=0`) leaves the fixed-loop simulation unchanged.
- No route grant bypasses occupancy, hazard, or restrictive-zone checks.
