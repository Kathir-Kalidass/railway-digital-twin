# Stage A2 (S0) — Multi-Train Block Signalling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the authoritative backend from one aggregate train + hazard-only zone signals to a deterministic, multi-train, block-based signalling model with layered aspects.

**Architecture:** A topology builder derives a double-track ring of ordered blocks from config. A pure `signalling` module derives per-block aspects (occupancy + lookahead + hazard, most-restrictive wins). `makeState` owns authoritative `trains[]`/`blocks[]`/`lines[]`/`station` and a fixed-timestep `tick(dtSec)`. The bus publishes retained per-block signals. Ingestion keeps only wildlife/sensor telemetry; the legacy unauthenticated `/api/event` route is removed.

**Tech Stack:** Node.js (ESM), `express`, `mqtt`, `node:test` + `assert/strict`, `better-sqlite3`. No new dependencies.

**Spec:** [`../specs/2026-10-19-stage-a2-block-signalling-design.md`](../specs/2026-10-19-stage-a2-block-signalling-design.md)

## Global Constraints

- ESM only; tests run with `cd backend && npm test` (`node --env-file-if-exists=.env.test --test`).
- Do not add npm dependencies.
- Zones are exactly `['zone1','zone2']`.
- Speeds clamp to `0..80` km/h inclusive.
- Illustrative dynamics: brake `2.0 m/s²`, accel `0.6 m/s²`, caution `30 km/h`. Not certified.
- Simulation is deterministic: fixed tick, integer tick counter, no wall-clock in physics.
- MQTT snapshots publish at ≤ 2 Hz.
- Least-privilege ACLs only; never `railway/#`. Godot must lose `zoneN/train` write.
- `POST /api/event` is removed and returns 404.
- `railway/zoneN/train` is retired (no publish, no ingest).
- The legacy `snapshot().train` field is retained as a **deprecated** summary derived from `trains[0]`.
- Every commit message uses the repo's `feat:` / `fix:` / `test:` style.

## File Structure

- Create `backend/src/railway.js` — topology builder (`buildTopology`, `blockById`, `nextBlockId`).
- Create `backend/src/signalling.js` — pure aspect derivation (`mostRestrictive`, `isZoneRestrictive`, `deriveBlockAspects`, `zoneSignal`).
- Create `backend/src/simulation.js` — pure fixed-step train integration (`stepTrains`, `occupyBlocks`).
- Modify `backend/src/config.js` — add `topology`, `trains`, `simulation`; add `validateConfig`.
- Modify `backend/src/state.js` — authoritative multi-train model, `tick`, `setWildlife`, `setSensor`, `applySpeed({trainId})`.
- Modify `backend/src/bus.js` — publish retained `railway/signal/{blockId}`.
- Modify `backend/src/ingest.js` — drop `zoneN/train`; use `setWildlife`/`setSensor`.
- Modify `backend/src/validate.js` — `validateSpeed` accepts optional `trainId`.
- Modify `backend/src/routes/control.js` — `/api/speed` accepts optional `trainId`.
- Modify `backend/src/app.js` — remove `simulationRouter`.
- Delete `backend/src/routes/simulation.js`.
- Modify `backend/server.js` — build topology, start the tick loop, drop `zoneN/train` subscription.
- Modify `mosquitto/acl_file` — ACL deltas.
- Modify tests: `state.test.js`, `ingest.test.js`, `control_routes.test.js`, `broker_acl.test.js`, `e2e.test.js`; add `railway.test.js`, `signalling.test.js`, `simulation.test.js`, `read_routes.test.js` additions.

---

### Task 1: Topology builder and config

**Files:**
- Create: `backend/src/railway.js`
- Modify: `backend/src/config.js`
- Create: `backend/test/railway.test.js`
- Test: `backend/test/config.test.js`

**Interfaces:**
- Produces: `buildTopology(config) -> { blocks: Block[], lines: Line[], station: Station }`; `blockById(topology, id) -> Block | undefined`; `nextBlockId(topology, line, index) -> string`.
- Consumes: `config.topology` (see Global Constraints for defaults).

- [ ] **Step 1: Write the failing test**

Create `backend/test/railway.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildTopology, blockById, nextBlockId } from '../src/railway.js';

const config = { topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'Forest Halt', upIndex: 2, downIndex: 2, dwellSec: 20 } } };

test('builds both lines with ordered blocks and zone mapping', () => {
  const topo = buildTopology(config);
  assert.equal(topo.blocks.length, 10);
  assert.deepEqual(topo.lines[0].blocks, ['UP-B0', 'UP-B1', 'UP-B2', 'UP-B3', 'UP-B4']);
  assert.equal(blockById(topo, 'UP-B0').zone, 'zone1');
  assert.equal(blockById(topo, 'UP-B3').zone, 'zone2');
});

test('station maps to platform blocks', () => {
  const topo = buildTopology(config);
  assert.deepEqual(topo.station.blocks, { UP: 'UP-B2', DOWN: 'DOWN-B2' });
});

test('nextBlockId wraps the ring', () => {
  const topo = buildTopology(config);
  assert.equal(nextBlockId(topo, 'UP', 4), 'UP-B0');
  assert.equal(nextBlockId(topo, 'UP', 0), 'UP-B1');
});
```

Also amend `backend/test/config.test.js` to assert the new keys exist (append):

```js
test('config exposes topology, trains and simulation settings', () => {
  assert.equal(config.zones.length, 2);
  assert.equal(config.trains.length, 4);
  assert.equal(config.topology.lines.length, 2);
  assert.ok(config.simulation.tickMs > 0);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && node --test test/railway.test.js`
Expected: FAIL (`Cannot find module '../src/railway.js'`).

- [ ] **Step 3: Implement `railway.js`**

Create `backend/src/railway.js`:

```js
export function buildTopology(config) {
  const t = config.topology;
  const blocks = [];
  const lines = [];
  for (const line of t.lines) {
    const ids = [];
    for (let i = 0; i < t.blocksPerLine; i++) {
      const id = `${line}-B${i}`;
      blocks.push({ id, line, index: i, zone: t.zoneByIndex[i], lengthM: t.blockLengthM, occupiedBy: null });
      ids.push(id);
    }
    lines.push({ id: line, blocks: ids });
  }
  const station = { ...t.station, blocks: { UP: `UP-B${t.station.upIndex}`, DOWN: `DOWN-B${t.station.downIndex}` } };
  return { blocks, lines, station };
}

export function blockById(topology, id) {
  return topology.blocks.find((b) => b.id === id);
}

export function nextBlockId(topology, line, index) {
  const lineObj = topology.lines.find((l) => l.id === line);
  const n = lineObj.blocks.length;
  return `${line}-B${(index + 1) % n}`;
}
```

- [ ] **Step 4: Extend `config.js`**

Modify `backend/src/config.js` — add before `seedUsers`:

```js
  topology: {
    lines: ['UP', 'DOWN'],
    blocksPerLine: 5,
    blockLengthM: 300,
    zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'],
    station: { id: 'station', name: 'Forest Halt', upIndex: 2, downIndex: 2, dwellSec: 20 },
  },
  trains: [
    { id: 'T1', line: 'UP', direction: 'UP', startBlock: 0, startOffsetM: 0, lengthM: 60 },
    { id: 'T2', line: 'UP', direction: 'UP', startBlock: 2, startOffsetM: 0, lengthM: 90 },
    { id: 'T3', line: 'DOWN', direction: 'DOWN', startBlock: 0, startOffsetM: 0, lengthM: 60 },
    { id: 'T4', line: 'DOWN', direction: 'DOWN', startBlock: 3, startOffsetM: 0, lengthM: 90 },
  ],
  simulation: {
    tickMs: 500,
    lookaheadBlocks: 2,
    cautionSpeedKmh: 30,
    brakeMps2: 2.0,
    accelMps2: 0.6,
    defaultTargetSpeedKmh: 48,
  },
```

And append a validator at the end of `config.js`:

```js
export function validateConfig(c) {
  const errors = [];
  const zones = new Set(c.zones);
  for (const [i, z] of c.topology.zoneByIndex.entries()) if (!zones.has(z)) errors.push(`zoneByIndex[${i}] unknown zone ${z}`);
  for (const t of c.trains) {
    if (!c.topology.lines.includes(t.line)) errors.push(`train ${t.id} unknown line ${t.line}`);
    if (t.startBlock < 0 || t.startBlock >= c.topology.blocksPerLine) errors.push(`train ${t.id} startBlock out of range`);
    if (!(t.lengthM > 0)) errors.push(`train ${t.id} lengthM must be > 0`);
  }
  if (!(c.simulation.tickMs > 0)) errors.push('simulation.tickMs must be > 0');
  if (errors.length) throw new Error(`invalid config: ${errors.join('; ')}`);
  return true;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && node --test test/railway.test.js test/config.test.js`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/src/railway.js backend/src/config.js backend/test/railway.test.js backend/test/config.test.js
git commit -m "feat(backend): add railway topology builder and config"
```

---

### Task 2: Signalling derivation

**Files:**
- Create: `backend/src/signalling.js`
- Create: `backend/test/signalling.test.js`

**Interfaces:**
- Consumes: `topology` (Task 1), `blocks` (array with `id`,`line`,`index`,`zone`,`occupiedBy`), `zones` map, `config.simulation.lookaheadBlocks`.
- Produces: `mostRestrictive(a,b) -> 'RED'|'YELLOW'|'GREEN'`; `isZoneRestrictive(zone) -> boolean`; `deriveBlockAspects({ topology, blocks, zones, lookaheadBlocks }) -> Record<blockId, aspect>` (per-block aspects include occupancy + that block's zone hazard); `zoneSignal(zoneId, zones) -> 'RED'|'YELLOW'|'GREEN'` (hazard-layer zone aggregate: `RED` if the zone is restrictive, else `YELLOW` if any other zone is restrictive, else `GREEN`).
- **Ruling (preflight):** the *zone* signal is the hazard-layer aggregate (Stage A back-compat), **not** the occupancy-driven block aggregate. Occupancy drives **per-block** signals only. This preserves baseline behaviour (`read_routes` expects `zone1` GREEN at rest; `e2e`/`state` expect the non-hazard zone `YELLOW`) while per-block signals carry approach/occupancy. This intentionally interprets spec §4.4's "never less restrictive than the existing Stage A hazard result" as the zone aggregate; it deviates from a literal reading of "most restrictive among its blocks".

- [ ] **Step 1: Write the failing test**

Create `backend/test/signalling.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildTopology } from '../src/railway.js';
import { deriveBlockAspects, zoneSignal, mostRestrictive, isZoneRestrictive } from '../src/signalling.js';

const config = { topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'x', upIndex: 2, downIndex: 2, dwellSec: 20 } } };
const zones = () => ({ zone1: { wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' }, zone2: { wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' } });

test('mostRestrictive orders GREEN < YELLOW < RED', () => {
  assert.equal(mostRestrictive('GREEN', 'YELLOW'), 'YELLOW');
  assert.equal(mostRestrictive('YELLOW', 'RED'), 'RED');
  assert.equal(mostRestrictive('GREEN', 'GREEN'), 'GREEN');
});

test('clear line yields all GREEN', () => {
  const topo = buildTopology(config);
  const a = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones: zones(), lookaheadBlocks: 2 });
  assert.ok(Object.values(a).every((v) => v === 'GREEN'));
});

test('occupancy: occupied block RED, block behind YELLOW', () => {
  const topo = buildTopology(config);
  const blocks = topo.blocks.map((b) => ({ ...b }));
  blocks.find((b) => b.id === 'UP-B3').occupiedBy = 'T1';
  const a = deriveBlockAspects({ topology: topo, blocks, zones: zones(), lookaheadBlocks: 2 });
  assert.equal(a['UP-B3'], 'RED');
  assert.equal(a['UP-B2'], 'YELLOW');
  assert.equal(a['UP-B0'], 'GREEN');
});

test('zone hazard forces every block in the zone RED', () => {
  const topo = buildTopology(config);
  const z = zones(); z.zone1.wildlifeDetected = true;
  const a = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones: z, lookaheadBlocks: 2 });
  assert.equal(a['UP-B0'], 'RED');
  assert.equal(a['UP-B1'], 'RED');
  assert.equal(a['UP-B3'], 'GREEN');
});

test('zoneSignal reflects hazard layer and cross-zone caution', () => {
  const z = zones();
  assert.equal(zoneSignal('zone1', z), 'GREEN');
  assert.equal(zoneSignal('zone2', z), 'GREEN');
  z.zone1.wildlifeDetected = true;
  assert.equal(zoneSignal('zone1', z), 'RED');
  assert.equal(zoneSignal('zone2', z), 'YELLOW');
  z.zone2.sensorHealthy = false;
  assert.equal(zoneSignal('zone2', z), 'RED');
});

test('isZoneRestrictive covers wildlife, fault, recovery', () => {
  assert.equal(isZoneRestrictive({ wildlifeDetected: true, sensorHealthy: true, status: 'NORMAL' }), true);
  assert.equal(isZoneRestrictive({ wildlifeDetected: false, sensorHealthy: false, status: 'NORMAL' }), true);
  assert.equal(isZoneRestrictive({ wildlifeDetected: false, sensorHealthy: true, status: 'RECOVERY_REQUIRED' }), true);
  assert.equal(isZoneRestrictive({ wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' }), false);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/signalling.test.js`
Expected: FAIL (`Cannot find module '../src/signalling.js'`).

- [ ] **Step 3: Implement `signalling.js`**

Create `backend/src/signalling.js`:

```js
const ORDER = { GREEN: 0, YELLOW: 1, RED: 2 };

export function mostRestrictive(a, b) {
  return ORDER[a] >= ORDER[b] ? a : b;
}

export function isZoneRestrictive(z) {
  return Boolean(z.wildlifeDetected) || !z.sensorHealthy || z.status === 'RECOVERY_REQUIRED';
}

export function deriveBlockAspects({ topology, blocks, zones, lookaheadBlocks = 2 }) {
  const byId = new Map(blocks.map((b) => [b.id, b]));
  const occupied = new Set(blocks.filter((b) => b.occupiedBy).map((b) => b.id));
  const aspects = {};
  for (const line of topology.lines) {
    const ids = line.blocks;
    const n = ids.length;
    for (let i = 0; i < n; i++) {
      const block = byId.get(ids[i]);
      let aspect = 'GREEN';
      if (occupied.has(block.id)) {
        aspect = 'RED';
      } else {
        let yellow = false;
        for (let k = 1; k <= lookaheadBlocks; k++) {
          if (occupied.has(ids[(i + k) % n])) { yellow = true; break; }
        }
        aspect = yellow ? 'YELLOW' : 'GREEN';
      }
      if (isZoneRestrictive(zones[block.zone])) aspect = mostRestrictive(aspect, 'RED');
      aspects[block.id] = aspect;
    }
  }
  return aspects;
}

export function zoneSignal(zoneId, zones) {
  if (isZoneRestrictive(zones[zoneId])) return 'RED';
  const otherRestrictive = Object.keys(zones).some((id) => id !== zoneId && isZoneRestrictive(zones[id]));
  return otherRestrictive ? 'YELLOW' : 'GREEN';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/signalling.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/signalling.js backend/test/signalling.test.js
git commit -m "feat(backend): add layered block signalling derivation"
```

---

### Task 3: Simulation step

**Files:**
- Create: `backend/src/simulation.js`
- Create: `backend/test/simulation.test.js`

**Interfaces:**
- Consumes: `topology`, `simulation` config, `zones`, `trains` (array), `dtSec`.
- Produces: `occupyBlocks(topology, trains) -> void` (sets `block.occupiedBy`); `stepTrains({ topology, simulation, zones, trains, dtSec }) -> trains` (mutates and returns trains; sets `status`, `speedKmh`, `block`, `offsetM`, `targetSpeedKmh`).

- [ ] **Step 1: Write the failing test**

Create `backend/test/simulation.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildTopology } from '../src/railway.js';
import { deriveBlockAspects } from '../src/signalling.js';
import { occupyBlocks, stepTrains } from '../src/simulation.js';

const config = { topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'x', upIndex: 2, downIndex: 2, dwellSec: 20 } } };
const sim = { lookaheadBlocks: 2, cautionSpeedKmh: 30, brakeMps2: 2.0, accelMps2: 0.6, defaultTargetSpeedKmh: 48 };
const zones = () => ({ zone1: { targetSpeedKmh: 48, wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' }, zone2: { targetSpeedKmh: 48, wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' } });
const train = (o = {}) => ({ id: 'T1', line: 'UP', direction: 'UP', block: 'UP-B0', offsetM: 0, speedKmh: 0, targetSpeedKmh: 48, lengthM: 60, status: 'RUNNING', zone: 'zone1', ...o });

test('occupyBlocks marks every block overlapped by the consist', () => {
  const topo = buildTopology(config);
  occupyBlocks(topo, [train({ offsetM: 280, lengthM: 60 })]); // 20m left in B0, 40m into B1
  assert.equal(topo.blocks.find((b) => b.id === 'UP-B0').occupiedBy, 'T1');
  assert.equal(topo.blocks.find((b) => b.id === 'UP-B1').occupiedBy, 'T1');
  assert.equal(topo.blocks.find((b) => b.id === 'UP-B2').occupiedBy, null);
});

test('accelerates toward target and advances position', () => {
  const topo = buildTopology(config);
  const t = train();
  stepTrains({ topology: topo, simulation: sim, zones: zones(), trains: [t], dtSec: 1 });
  assert.ok(t.speedKmh > 0);
  assert.ok(t.offsetM > 0);
});

test('unoccupied block folds into the next block on wrap-free travel', () => {
  const topo = buildTopology(config);
  const t = train({ offsetM: 299, speedKmh: 80 });
  stepTrains({ topology: topo, simulation: sim, zones: zones(), trains: [t], dtSec: 1 });
  assert.equal(t.block, 'UP-B1');
  assert.ok(t.offsetM >= 0 && t.offsetM < 300);
});

test('RED aspect ahead holds the train', () => {
  const topo = buildTopology(config);
  const t = train({ block: 'UP-B0', offsetM: 0, speedKmh: 40 });
  const blocks = topo.blocks.map((b) => ({ ...b }));
  blocks.find((b) => b.id === 'UP-B1').occupiedBy = 'T2';
  const aspects = deriveBlockAspects({ topology: topo, blocks, zones: zones(), lookaheadBlocks: 2 });
  stepTrains({ topology: topo, simulation: sim, zones: zones(), trains: [t], dtSec: 1, aspects });
  assert.ok(t.targetSpeedKmh < 40);
});

test('deterministic for a fixed number of equal steps', () => {
  const run = () => {
    const topo = buildTopology(config);
    const t = train();
    for (let i = 0; i < 20; i++) stepTrains({ topology: topo, simulation: sim, zones: zones(), trains: [t], dtSec: 0.5 });
    return t;
  };
  const a = run(); const b = run();
  assert.equal(a.offsetM, b.offsetM);
  assert.equal(a.speedKmh, b.speedKmh);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/simulation.test.js`
Expected: FAIL (`Cannot find module '../src/simulation.js'`).

- [ ] **Step 3: Implement `simulation.js`**

Create `backend/src/simulation.js`:

```js
import { isZoneRestrictive } from './signalling.js';

const clampSpeed = (v) => Math.max(0, Math.min(80, v));

export function occupyBlocks(topology, trains) {
  for (const b of topology.blocks) b.occupiedBy = null;
  for (const t of trains) {
    const line = topology.lines.find((l) => l.id === t.line);
    const n = line.blocks.length;
    let idx = line.blocks.indexOf(t.block);
    let remaining = t.offsetM + t.lengthM;
    let first = true;
    while (remaining > 0) {
      const block = topology.blocks.find((b) => b.id === line.blocks[idx]);
      if (first) { block.occupiedBy = t.id; remaining -= block.lengthM - t.offsetM; first = false; }
      else { block.occupiedBy = t.id; remaining -= block.lengthM; }
      idx = (idx + 1) % n;
      if (remaining <= 0) break;
    }
  }
}

function permittedTarget({ topology, simulation, zones, aspects, t }) {
  const line = topology.lines.find((l) => l.id === t.line);
  const idx = line.blocks.indexOf(t.block);
  const nextId = line.blocks[(idx + 1) % line.blocks.length];
  const zone = zones[t.zone];
  const base = t.commandedSpeedKmh != null ? t.commandedSpeedKmh : (zone ? zone.targetSpeedKmh : simulation.defaultTargetSpeedKmh);
  let target = base;
  const nextAspect = aspects ? aspects[nextId] : 'GREEN';
  if (nextAspect === 'RED') target = 0;
  else if (nextAspect === 'YELLOW') target = Math.min(target, simulation.cautionSpeedKmh);
  return target;
}

export function stepTrains({ topology, simulation, zones, trains, dtSec, aspects }) {
  for (const t of trains) {
    const line = topology.lines.find((l) => l.id === t.line);
    const block = topology.blocks.find((b) => b.id === t.block);
    t.zone = block.zone;
    const zone = zones[t.zone];
    if (zone && isZoneRestrictive(zone)) t.status = 'EMERGENCY';
    else if (t.status === 'EMERGENCY' && !(zone && isZoneRestrictive(zone))) t.status = 'DWELL';

    const target = t.status === 'EMERGENCY' ? 0 : permittedTarget({ topology, simulation, zones, aspects, t });
    t.targetSpeedKmh = clampSpeed(target);
    const rate = t.speedKmh > t.targetSpeedKmh ? simulation.brakeMps2 : simulation.accelMps2;
    const deltaKmh = rate * 3.6 * dtSec;
    t.speedKmh = clampSpeed(t.speedKmh < t.targetSpeedKmh ? Math.min(t.targetSpeedKmh, t.speedKmh + deltaKmh) : Math.max(t.targetSpeedKmh, t.speedKmh - deltaKmh));

    let advance = (t.speedKmh / 3.6) * dtSec;
    while (advance > 0) {
      const cur = topology.blocks.find((b) => b.id === t.block);
      const room = cur.lengthM - t.offsetM;
      if (advance < room) { t.offsetM += advance; advance = 0; }
      else {
        advance -= room;
        const nextIdx = (cur.index + 1) % line.blocks.length;
        t.block = line.blocks[nextIdx];
        t.offsetM = 0;
      }
    }
    occupyBlocks(topology, trains);
  }
  return trains;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/simulation.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/simulation.js backend/test/simulation.test.js
git commit -m "feat(backend): add deterministic multi-train simulation step"
```

---

### Task 4: State integration

**Files:**
- Modify: `backend/src/state.js`
- Modify: `backend/test/state.test.js`

**Interfaces:**
- Consumes: `buildTopology` (Task 1), `deriveBlockAspects`/`zoneSignal` (Task 2), `occupyBlocks`/`stepTrains` (Task 3).
- Produces: `makeState({ config, topology })` returning `{ snapshot, applyCommand, applySpeed, setWildlife, setSensor, tick, setBrokerConnected }`.
- `snapshot()` returns `{ zones, train, trains, lines, blocks, station, comm, overall, lastEvent, updatedAt }` where `zones[z].signal` is the hazard-layer aggregate (`zoneSignal`), each `blocks[i].signal` carries the occupancy-aware aspect, and `zones[z].blocks` lists block ids. Per-train speed is honored via `trains[i].commandedSpeedKmh`.

- [ ] **Step 1: Write the failing test**

Replace `backend/test/state.test.js` with:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeState } from '../src/state.js';
import { buildTopology } from '../src/railway.js';

const config = { zones: ['zone1', 'zone2'], topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'x', upIndex: 2, downIndex: 2, dwellSec: 20 } }, trains: [{ id: 'T1', line: 'UP', direction: 'UP', startBlock: 0, startOffsetM: 0, lengthM: 60 }], simulation: { tickMs: 500, lookaheadBlocks: 2, cautionSpeedKmh: 30, brakeMps2: 2.0, accelMps2: 0.6, defaultTargetSpeedKmh: 48 } };
const env = (zone, event) => ({ request_id: `${event}-${zone}`, zone, event, timestamp: new Date().toISOString(), source: 'dashboard', payload: {} });
const mk = () => makeState({ config, topology: buildTopology(config) });

test('wildlife in zone1 makes zone1 RED and zone2 YELLOW, zones independent', () => {
  const s = mk();
  assert.equal(s.applyCommand(env('zone1', 'WILDLIFE_DETECTED')).ok, true);
  const snap = s.snapshot();
  assert.equal(snap.zones.zone1.signal, 'RED');
  assert.equal(snap.zones.zone2.signal, 'YELLOW');
  assert.equal(snap.zones.zone2.wildlifeDetected, false);
  assert.equal(snap.overall, 'HAZARD');
});

test('clearing wildlife requires reset and stays restrictive', () => {
  const s = mk();
  s.applyCommand(env('zone1', 'WILDLIFE_DETECTED'));
  s.applyCommand(env('zone1', 'WILDLIFE_CLEARED'));
  assert.equal(s.snapshot().zones.zone1.signal, 'RED');
  assert.equal(s.snapshot().overall, 'RECOVERY_REQUIRED');
  assert.equal(s.applyCommand(env('zone1', 'RESET')).ok, true);
  assert.equal(s.snapshot().overall, 'NORMAL');
});

test('reset is rejected while hazard active', () => {
  const s = mk();
  s.applyCommand(env('zone2', 'SENSOR_FAULT'));
  const r = s.applyCommand(env('zone2', 'RESET'));
  assert.equal(r.ok, false);
  assert.match(r.reason, /reject/i);
});

test('snapshot exposes authoritative trains, blocks, lines, station', () => {
  const s = mk();
  const snap = s.snapshot();
  assert.equal(snap.trains.length, 1);
  assert.equal(snap.trains[0].id, 'T1');
  assert.equal(snap.lines.length, 2);
  assert.equal(snap.blocks.length, 10);
  assert.ok(snap.station.blocks.UP);
  assert.deepEqual(snap.zones.zone1.blocks.sort(), ['DOWN-B0', 'DOWN-B1', 'DOWN-B2', 'UP-B0', 'UP-B1', 'UP-B2']);
  assert.equal(snap.blocks.find((b) => b.id === 'UP-B0').signal, 'RED'); // occupancy drives per-block aspect
  assert.equal(snap.train.id, 'T1'); // deprecated summary
});

test('tick advances trains and reflects occupancy in aspects', () => {
  const s = mk();
  s.setBrokerConnected(true);
  const before = s.snapshot().trains[0].offsetM;
  s.tick(1);
  assert.ok(s.snapshot().trains[0].offsetM > before);
});

test('per-train speed control and stopping distance', () => {
  const s = mk();
  assert.equal(s.applySpeed({ trainId: 'T1', speedKmh: 0 }).ok, true);
  assert.equal(s.snapshot().trains[0].targetSpeedKmh, 0);
  assert.equal(s.snapshot().trains[0].stoppingDistanceM >= 0, true);
});

test('applySpeed rejects unknown train', () => {
  const s = mk();
  assert.equal(s.applySpeed({ trainId: 'NOPE', speedKmh: 10 }).ok, false);
});

test('broker disconnect forces restrictive overall state', () => {
  const s = mk();
  s.setBrokerConnected(false);
  assert.equal(s.snapshot().overall, 'COMM_LOST');
  s.setBrokerConnected(true);
  assert.equal(s.snapshot().overall, 'NORMAL');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/state.test.js`
Expected: FAIL (`applySpeed`/`tick`/`setWildlife` undefined; `trains` missing).

- [ ] **Step 3: Rewrite `state.js`**

Replace `backend/src/state.js` with:

```js
import { buildTopology } from './railway.js';
import { deriveBlockAspects, zoneSignal } from './signalling.js';
import { occupyBlocks, stepTrains } from './simulation.js';

const DECEL = 2.0; // m/s^2 illustrative braking
const DEFAULT_TARGET = 48;

function newZone(id) {
  return { id, trainPresent: false, wildlifeDetected: false, sensorHealthy: true, signal: 'GREEN', status: 'NORMAL', targetSpeedKmh: DEFAULT_TARGET, blocks: [] };
}

export function makeState({ config, topology }) {
  const topo = topology || buildTopology(config);
  const sim = config.simulation || { lookaheadBlocks: 2, cautionSpeedKmh: 30, brakeMps2: 2.0, accelMps2: 0.6, defaultTargetSpeedKmh: DEFAULT_TARGET };
  const zones = {};
  for (const id of config.zones) zones[id] = newZone(id);
  for (const b of topo.blocks) zones[b.zone].blocks.push(b.id);

  const trains = (config.trains || []).map((t) => ({
    id: t.id, line: t.line, direction: t.direction,
    block: `${t.line}-B${t.startBlock}`, offsetM: t.startOffsetM,
    speedKmh: 0, targetSpeedKmh: zones[topo.blocks.find((b) => b.id === `${t.line}-B${t.startBlock}`).zone].targetSpeedKmh,
    commandedSpeedKmh: null,
    lengthM: t.lengthM, status: 'RUNNING', zone: topo.blocks.find((b) => b.id === `${t.line}-B${t.startBlock}`).zone,
  }));
  occupyBlocks(topo, trains);

  const comm = { mqttConnected: true };
  let lastEvent = 'System initialized';
  let tickCount = 0;

  const isRestrictive = (z) => z.wildlifeDetected || !z.sensorHealthy || z.status === 'RECOVERY_REQUIRED';

  function recomputeOverall() {
    const anyWildlife = config.zones.some((id) => zones[id].wildlifeDetected);
    const anyFault = config.zones.some((id) => !zones[id].sensorHealthy);
    const anyRestrictive = config.zones.some((id) => isRestrictive(zones[id]));
    if (!comm.mqttConnected) return 'COMM_LOST';
    if (anyFault) return 'SENSOR_FAULT';
    if (anyWildlife) return 'HAZARD';
    if (anyRestrictive) return 'RECOVERY_REQUIRED';
    return 'NORMAL';
  }

  function snapshot() {
    const aspects = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones, lookaheadBlocks: sim.lookaheadBlocks });
    for (const id of config.zones) {
      zones[id].signal = zoneSignal(id, zones);
      zones[id].trainPresent = trains.some((t) => t.zone === id);
    }
    const outTrains = trains.map((t) => ({ ...t, stoppingDistanceM: Math.round((t.speedKmh / 3.6) ** 2 / (2 * DECEL)) }));
    const primary = outTrains[0] || null;
    return {
      zones: JSON.parse(JSON.stringify(zones)),
      train: primary, // DEPRECATED: summary of trains[0] for un-migrated clients
      trains: outTrains,
      lines: topo.lines.map((l) => ({ id: l.id, blocks: [...l.blocks] })),
      blocks: topo.blocks.map((b) => ({ ...b, signal: aspects[b.id] || 'GREEN' })),
      station: { ...topo.station, blocks: { ...topo.station.blocks } },
      comm: { ...comm },
      overall: recomputeOverall(),
      lastEvent,
      updatedAt: new Date().toISOString(),
    };
  }

  function applyCommand(env) {
    const z = zones[env.zone];
    if (!z) return { ok: false, reason: 'unknown zone' };
    switch (env.event) {
      case 'WILDLIFE_DETECTED': z.wildlifeDetected = true; z.status = 'HAZARD'; z.targetSpeedKmh = 0; break;
      case 'WILDLIFE_CLEARED': z.wildlifeDetected = false; z.status = 'RECOVERY_REQUIRED'; break;
      case 'SENSOR_FAULT': z.sensorHealthy = false; z.status = 'SENSOR_FAULT'; z.targetSpeedKmh = 0; break;
      case 'SENSOR_RESTORED': z.sensorHealthy = true; z.status = 'RECOVERY_REQUIRED'; break;
      case 'TRAIN_ENTERED_ZONE': z.trainPresent = true; break;
      case 'TRAIN_LEFT_ZONE': z.trainPresent = false; break;
      case 'RESET':
        if (z.sensorHealthy && !z.wildlifeDetected) { z.status = 'NORMAL'; z.targetSpeedKmh = DEFAULT_TARGET; }
        else return { ok: false, reason: 'reset rejected: active hazard or sensor fault' };
        break;
      default: return { ok: false, reason: 'unsupported event' };
    }
    lastEvent = env.event;
    return { ok: true };
  }

  function applySpeed({ zone, trainId, speedKmh }) {
    const v = Math.max(0, Math.min(80, Number(speedKmh)));
    if (trainId) {
      const t = trains.find((x) => x.id === trainId);
      if (!t) return { ok: false, reason: 'unknown train' };
      t.commandedSpeedKmh = v;
      t.targetSpeedKmh = v;
      return { ok: true };
    }
    const z = zones[zone];
    if (!z) return { ok: false, reason: 'unknown zone' };
    z.targetSpeedKmh = v;
    return { ok: true };
  }

  function setWildlife(zone, value) { const z = zones[zone]; if (z) { z.wildlifeDetected = Boolean(value); if (value) { z.status = 'HAZARD'; z.targetSpeedKmh = 0; } } }
  function setSensor(zone, value) { const z = zones[zone]; if (z) { z.sensorHealthy = Boolean(value); if (value === false) { z.status = 'SENSOR_FAULT'; z.targetSpeedKmh = 0; } } }

  function tick(dtSec) {
    if (!comm.mqttConnected) return trains;
    tickCount += 1;
    const aspects = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones, lookaheadBlocks: sim.lookaheadBlocks });
    stepTrains({ topology: topo, simulation: sim, zones, trains, dtSec, aspects });
    occupyBlocks(topo, trains);
    return trains;
  }

  function setBrokerConnected(value) { comm.mqttConnected = Boolean(value); }

  return { snapshot, applyCommand, applySpeed, setWildlife, setSensor, tick, setBrokerConnected, getTickCount: () => tickCount };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/state.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/state.js backend/test/state.test.js
git commit -m "feat(backend): authoritative multi-train state with layered signals"
```

---

### Task 5: Bus per-block signals

**Files:**
- Modify: `backend/src/bus.js`
- Modify: `backend/test/bus.test.js`

**Interfaces:**
- Consumes: `state.snapshot()` (now includes `blocks`).
- Produces: `snapshot()` also publishes retained `railway/signal/{blockId}` with `{ block, line, zone, signal, timestamp }`.

- [ ] **Step 1: Write the failing test**

Append to `backend/test/bus.test.js`:

```js
test('snapshot publishes retained per-block signals', () => {
  const mqtt = { published: [], publish(t, o, opts = {}) { this.published.push({ t, o, opts }); }, subscribe() {}, isConnected: () => true };
  const state = { snapshot: () => ({ zones: { zone1: { signal: 'GREEN' } }, blocks: [{ id: 'UP-B0', line: 'UP', zone: 'zone1', signal: 'RED' }], updatedAt: 'X' }) };
  const bus = makeBus({ mqtt, state, events: makeEvents() });
  bus.snapshot();
  const msg = mqtt.published.find((m) => m.t === 'railway/signal/UP-B0');
  assert.ok(msg);
  assert.equal(msg.opts.retain, true);
  assert.equal(msg.o.signal, 'RED');
});
```

Also fix the two existing `makeState({ config: { zones: [...] } })` calls (lines 13 and 25): `makeState` now calls `buildTopology(config)`, which throws without a topology. Add `import { buildTopology } from '../src/railway.js';` and a shared config, then use it in both tests:

```js
const testConfig = { zones: ['zone1', 'zone2'], topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'x', upIndex: 2, downIndex: 2, dwellSec: 20 } }, trains: [], simulation: { tickMs: 500, lookaheadBlocks: 2, cautionSpeedKmh: 30, brakeMps2: 2.0, accelMps2: 0.6, defaultTargetSpeedKmh: 48 } };
const makeTestState = () => makeState({ config: testConfig, topology: buildTopology(testConfig) });
```

Replace both `makeState({ config: { zones: ['zone1', 'zone2'] } })` occurrences with `makeTestState()`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/bus.test.js`
Expected: FAIL (no `railway/signal/UP-B0` publish).

- [ ] **Step 3: Implement**

Replace the `snapshot()` body in `backend/src/bus.js` with:

```js
    snapshot() {
      const s = state.snapshot();
      mqtt.publish('railway/state', s, { retain: true });
      for (const id of Object.keys(s.zones)) {
        mqtt.publish(`railway/${id}/signal`, { zone: id, signal: s.zones[id].signal, timestamp: s.updatedAt }, { retain: true });
      }
      for (const b of s.blocks || []) {
        mqtt.publish(`railway/signal/${b.id}`, { block: b.id, line: b.line, zone: b.zone, signal: b.signal || 'GREEN', timestamp: s.updatedAt }, { retain: true });
      }
      return s;
    },
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/bus.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/bus.js backend/test/bus.test.js
git commit -m "feat(backend): publish retained per-block signal topics"
```

---

### Task 6: Ingestion changes

**Files:**
- Modify: `backend/src/ingest.js`
- Modify: `backend/test/ingest.test.js`

**Interfaces:**
- Consumes: `state.setWildlife(zone, bool)`, `state.setSensor(zone, bool)` (Task 4).
- Produces: `handle(topic, message)` ignores `railway/zoneN/train` with no state change.

- [ ] **Step 1: Write the failing test**

Replace `backend/test/ingest.test.js` with:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeState } from '../src/state.js';
import { makeEvents } from '../src/events.js';
import { makeBus } from '../src/bus.js';
import { makeIngest } from '../src/ingest.js';
import { buildTopology } from '../src/railway.js';

const config = { zones: ['zone1', 'zone2'], topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'x', upIndex: 2, downIndex: 2, dwellSec: 20 } }, trains: [{ id: 'T1', line: 'UP', direction: 'UP', startBlock: 0, startOffsetM: 0, lengthM: 60 }], simulation: { tickMs: 500, lookaheadBlocks: 2, cautionSpeedKmh: 30, brakeMps2: 2.0, accelMps2: 0.6, defaultTargetSpeedKmh: 48 } };
function fakeMqtt() { return { published: [], publish(t, o, opts = {}) { this.published.push({ t, o, opts }); }, subscribe() {}, isConnected: () => true }; }
function setup() {
  const mqtt = fakeMqtt();
  const state = makeState({ config, topology: buildTopology(config) });
  const bus = makeBus({ mqtt, state, events: makeEvents() });
  const ingest = makeIngest({ state, bus, config });
  return { mqtt, state, ingest };
}

test('zoneN/train is ignored (trains are authoritative)', () => {
  const { mqtt, state, ingest } = setup();
  state.setBrokerConnected(true);
  const before = state.snapshot().trains[0].speedKmh;
  ingest.handle('railway/zone1/train', { trainPresent: true, speedKmh: 20 });
  assert.equal(state.snapshot().trains[0].speedKmh, before);
  assert.equal(state.snapshot().zones.zone1.trainPresent, true); // T1 starts in zone1
});

test('zoneN/wildlife observation sets hazard', () => {
  const { state, ingest } = setup();
  state.setBrokerConnected(true);
  ingest.handle('railway/zone2/wildlife', { wildlifeDetected: true });
  assert.equal(state.snapshot().zones.zone2.wildlifeDetected, true);
  assert.equal(state.snapshot().overall, 'HAZARD');
});

test('esp32 telemetry marks fault', () => {
  const { state, ingest } = setup();
  state.setBrokerConnected(true);
  ingest.handle('railway/telemetry/esp32', { device: 'esp32', zone: 'zone2', sensorHealthy: false });
  assert.equal(state.snapshot().overall, 'SENSOR_FAULT');
});

test('disconnect sets COMM_LOST and reconnect reconciles', () => {
  const { state, ingest, mqtt } = setup();
  ingest.onBrokerConnected(true);
  assert.equal(state.snapshot().overall, 'NORMAL');
  ingest.onBrokerConnected(false);
  assert.equal(state.snapshot().overall, 'COMM_LOST');
  ingest.onBrokerConnected(true);
  assert.equal(state.snapshot().overall, 'NORMAL');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/ingest.test.js`
Expected: FAIL (ingest still calls removed `applyTelemetry`).

- [ ] **Step 3: Implement**

Replace `backend/src/ingest.js` with:

```js
export function makeIngest({ state, bus, config }) {
  function handle(topic, message = {}) {
    if (topic === 'railway/telemetry/esp32') {
      const zone = message.zone && config.zones.includes(message.zone) ? message.zone : null;
      if (typeof message.sensorHealthy === 'boolean') {
        const targets = zone ? [zone] : config.zones;
        for (const z of targets) state.setSensor(z, message.sensorHealthy);
        if (message.sensorHealthy === false) {
          bus.alert({ source: 'esp32', severity: 'HIGH', message: 'ESP32 reports sensor fault', zone, timestamp: new Date().toISOString() });
        }
        bus.snapshot();
      }
      return;
    }
    const wild = topic.match(/^railway\/(zone\d+)\/wildlife$/);
    if (wild) {
      const [, zone] = wild;
      if (!config.zones.includes(zone)) return;
      if (typeof message.wildlifeDetected === 'boolean') { state.setWildlife(zone, message.wildlifeDetected); bus.snapshot(); }
      return;
    }
    if (/^railway\/zone\d+\/train$/.test(topic)) return; // retired; trains are authoritative
    bus.event({ type: 'INVALID_TOPIC', topic });
  }

  function onBrokerConnected(connected) {
    state.setBrokerConnected(connected);
    if (connected) { bus.event({ type: 'BROKER_CONNECTED', message: 'Reconciling state from authoritative snapshot.' }); bus.snapshot(); }
    else { bus.event({ type: 'BROKER_DISCONNECTED', message: 'Communication lost; restrictive state applied.' }); bus.snapshot(); }
  }

  return { handle, onBrokerConnected };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/ingest.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/ingest.js backend/test/ingest.test.js
git commit -m "feat(backend): ingest wildlife/sensor only; retire train telemetry"
```

---

### Task 7: REST — retire `/api/event`, extend `/api/speed`

**Files:**
- Delete: `backend/src/routes/simulation.js`
- Modify: `backend/src/app.js`
- Modify: `backend/src/validate.js`
- Modify: `backend/src/routes/control.js`
- Modify: `backend/test/control_routes.test.js`, `backend/test/validate.test.js`

**Interfaces:**
- `validateSpeed(body, { zones, trains }) -> { ok, value: { zone?, trainId?, speedKmh } }`.
- `/api/speed` accepts optional `trainId`; unknown id → `400 { error: 'invalid speed', reason }`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/test/control_routes.test.js`:

```js
test('/api/speed accepts a known trainId', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const { body: { token } } = await login(url, 'operator', 'operator-dev-pass');
    const res = await fetch(`${url}/api/speed`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ zone: 'zone1', trainId: 'T1', speedKmh: 10 }) });
    assert.equal(res.status, 200);
    assert.equal(deps.state.snapshot().trains.find((t) => t.id === 'T1').targetSpeedKmh, 10);
  });
});

test('/api/speed rejects an unknown trainId with 400', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const { body: { token } } = await login(url, 'operator', 'operator-dev-pass');
    const res = await fetch(`${url}/api/speed`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ zone: 'zone1', trainId: 'NOPE', speedKmh: 10 }) });
    assert.equal(res.status, 400);
  });
});

test('/api/event is gone (404)', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const res = await fetch(`${url}/api/event`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ type: 'RESET', zone: 'zone1' }) });
    assert.equal(res.status, 404);
  });
});
```

Note: `buildDeps()` must use a topology-aware state. Amend `backend/test/app_helpers.js` so `makeState` receives a topology:

```js
import { buildTopology } from '../src/railway.js';
// inside buildDeps:
const state = makeState({ config, topology: buildTopology(config) });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && node --test test/control_routes.test.js`
Expected: FAIL (unknown trainId returns 200 applying zone speed; `/api/event` returns 200).

- [ ] **Step 3: Implement**

Update `backend/src/validate.js` `validateSpeed`:

```js
export function validateSpeed(body, { zones, trains = [] }) {
  const zone = String(body?.zone || '').toLowerCase();
  const trainId = body?.trainId ? String(body.trainId) : null;
  const speedKmh = Number(body?.speedKmh);
  if (trainId && !trains.some((t) => t.id === trainId)) return { ok: false, reason: 'unknown train' };
  if (!trainId && !zones.includes(zone)) return { ok: false, reason: 'invalid zone' };
  if (!Number.isFinite(speedKmh) || speedKmh < 0 || speedKmh > 80) return { ok: false, reason: 'speed must be 0..80' };
  return { ok: true, value: trainId ? { trainId, speedKmh, zone } : { zone, speedKmh } };
}
```

Update `backend/src/routes/control.js` `/api/speed` to pass `trains` and publish target by train or zone:

```js
  const ctx = { zones: config.zones, trains: (state.snapshot().trains || []).map((t) => ({ id: t.id })) };
```
(replace the existing `const ctx = { zones: config.zones };` at the top of the router factory).

And after `state.applySpeed(check.value)`, publish:

```js
    mqtt.publish(`railway/speed/${check.value.zone}`, { zone: check.value.zone, trainId: check.value.trainId || null, speedKmh: check.value.speedKmh, timestamp: new Date().toISOString() });
```

Delete `backend/src/routes/simulation.js` and remove its import/use from `backend/src/app.js`:

```js
import express from 'express';
import cors from 'cors';
import { authRouter } from './routes/auth.js';
import { healthRouter } from './routes/health.js';
import { controlRouter } from './routes/control.js';
import { stateRouter } from './routes/state.js';

export function createApp(deps) {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '32kb' }));
  app.use(authRouter(deps));
  app.use(healthRouter(deps));
  app.use(controlRouter(deps));
  app.use(stateRouter(deps));
  return app;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && node --test test/control_routes.test.js test/validate.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/control.js backend/src/validate.js backend/src/app.js backend/test/app_helpers.js backend/test/control_routes.test.js backend/test/validate.test.js
git rm backend/src/routes/simulation.js
git commit -m "feat(backend)!: remove /api/event and add per-train speed control"
```

---

### Task 8: Server wiring — topology, simulation loop, subscriptions

**Files:**
- Modify: `backend/server.js`
- Modify: `backend/src/config.js` (call `validateConfig`)
- Test: `backend/test/e2e.test.js` (loop behavior)

**Interfaces:**
- Server builds one `topology`, passes it to `makeState`, runs `setInterval` ticking `state.tick(tickMs/1000)` and calling `bus.snapshot()` at ≤2 Hz, and subscribes only to `railway/zone1/wildlife`, `railway/zone2/wildlife`, `railway/telemetry/esp32`.

- [ ] **Step 1: Implement** (wiring is covered by the e2e test in Step 2)

Rewrite `backend/server.js`:

```js
import { config, validateConfig } from './src/config.js';
import { buildTopology } from './src/railway.js';
import { openDb } from './src/db.js';
import { makeAudit } from './src/audit.js';
import { makeReplay } from './src/replay.js';
import { makeAuth } from './src/auth.js';
import { makeState } from './src/state.js';
import { makeEvents } from './src/events.js';
import { makeBus } from './src/bus.js';
import { makeMqtt } from './src/mqtt.js';
import { makeIngest } from './src/ingest.js';
import { createApp } from './src/app.js';

validateConfig(config);
const topology = buildTopology(config);
const db = openDb(config.dbPath);
const audit = makeAudit(db);
const replay = makeReplay(db);
const auth = makeAuth({ db, config });
auth.seedUsers();
const state = makeState({ config, topology });
state.setBrokerConnected(false);
const events = makeEvents();
let ingest;
const mqtt = makeMqtt({ config, onMessage: (topic, message) => ingest?.handle(topic, message) });
const bus = makeBus({ mqtt, state, events });
ingest = makeIngest({ state, bus, config });
mqtt.client.on('connect', () => {
  mqtt.subscribe(['railway/zone1/wildlife', 'railway/zone2/wildlife', 'railway/telemetry/esp32']);
  ingest.onBrokerConnected(true);
});
mqtt.client.on('close', () => ingest.onBrokerConnected(false));

let lastPublish = 0;
setInterval(() => {
  state.tick(config.simulation.tickMs / 1000);
  const now = Date.now();
  if (now - lastPublish >= 500) { lastPublish = now; bus.snapshot(); }
}, config.simulation.tickMs);

const app = createApp({ config, db, audit, replay, auth, state, bus, events, mqtt });
app.listen(config.port, '0.0.0.0', () => console.log(`Railway backend listening on :${config.port}; MQTT=${config.mqttUrl}`));
```

- [ ] **Step 2: Write/adjust e2e test**

Append to `backend/test/e2e.test.js`:

```js
test('state exposes multiple trains and block aspects', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const { body: { token } } = await login(url, 'viewer', 'viewer-dev-pass');
    const res = await fetch(`${url}/api/state`, { headers: { authorization: `Bearer ${token}` } });
    const snap = await res.json();
    assert.equal(snap.trains.length, 4);
    assert.equal(snap.blocks.length, 10);
    assert.ok(snap.blocks.every((b) => ['GREEN', 'YELLOW', 'RED'].includes(b.signal || 'GREEN')));
  });
});
```

- [ ] **Step 3: Run**

Run: `cd backend && node --test test/e2e.test.js`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add backend/server.js backend/src/config.js backend/test/e2e.test.js
git commit -m "feat(backend): wire topology + deterministic simulation loop"
```

---

### Task 9: ACL updates and broker ACL tests

**Files:**
- Modify: `mosquitto/acl_file`
- Modify: `backend/test/broker_acl.test.js`

**Interfaces:**
- Godot: no `zoneN/train` write; add `railway/signal/+` read.
- Backend: no `zoneN/train` read; add `railway/signal/+` write.
- Dashboard: add `railway/signal/+` read.

- [ ] **Step 1: Edit `mosquitto/acl_file`**

Under `user godot`: remove the two `topic write railway/zone{1,2}/train` lines; add:

```text
topic read railway/signal/+
```

Under `user backend`: remove `topic read railway/zone1/train` and `topic read railway/zone2/train`; add:

```text
topic write railway/signal/+
```

Under `user dashboard`: add:

```text
topic read railway/signal/+
```

- [ ] **Step 2: Update `broker_acl.test.js`**

Add cases (mirroring the file's existing style — requires Docker+broker via `scripts/test-backend.sh`):

```js
test('godot cannot write railway/zone1/train', async () => {
  await assertDenied('godot', { write: 'railway/zone1/train' });
});
test('godot can read railway/signal/UP-B0', async () => {
  await assertAllowed('godot', { read: 'railway/signal/UP-B0' });
});
test('dashboard can read railway/signal/UP-B0', async () => {
  await assertAllowed('dashboard', { read: 'railway/signal/UP-B0' });
});
```

(Use the file's existing helper names; if they differ, adapt these to the existing `assertAllowed`/`assertDenied` equivalents.)

- [ ] **Step 3: Restart broker and run ACL tests**

Run: `docker compose restart mqtt && bash scripts/test-backend.sh`
Expected: broker ACL suite PASS (allowed cases green, denied cases rejected).

- [ ] **Step 4: Commit**

```bash
git add mosquitto/acl_file backend/test/broker_acl.test.js
git commit -m "feat(acl): per-block signal topics; retire zoneN/train for godot"
```

---

### Task 10: Full regression and README note

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Full suite**

Run: `cd backend && npm test`
Expected: PASS (broker-dependent tests are skipped or run via `scripts/test-backend.sh`).

- [ ] **Step 2: Document the contract change in `README.md`**

Add a short subsection:

```markdown
### Multi-train block signalling (Stage A2)
The backend is authoritative for trains, blocks, and signal aspects. Godot and
the ESP32 publish only permitted telemetry; the dashboard controls via REST.
`POST /api/event` has been removed (it was an unauthenticated simulation shim).
Block signals are published retained on `railway/signal/{blockId}`.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document multi-train block signalling contract"
```

---

## Self-Review

**Spec coverage:** topology (§3, §10 → Task 1); layered signalling (§4 → Task 2); simulation loop (§5 → Tasks 3, 8); state contract (§6 → Task 4); topics/ACL (§7 → Tasks 5, 9); REST (§8 → Task 7); ingestion (§9 → Task 6); ripple (§11 → README + downstream stages); verification (§12 → tests across all tasks). No gaps.

**Placeholder scan:** No `TBD`/`TODO`; every code step contains complete code. Task 9's ACL test uses the file's existing helper names with an explicit instruction to adapt — this is a real integration file that must be read at execution time.

**Type consistency:** `buildTopology`/`blockById`/`nextBlockId` (Task 1) used consistently; `deriveBlockAspects`/`zoneSignal`/`isZoneRestrictive` (Task 2) reused in Tasks 3–4; `stepTrains`/`occupyBlocks` signatures (Task 3) match Task 4 calls; `applySpeed({zone,trainId,speedKmh})` matches Task 7 validate/route; `setWildlife`/`setSensor` match Task 6 ingest.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-19-stage-a2-block-signalling.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks.

**2. Inline Execution** — execute in-session with checkpoints (`superpowers:executing-plans`).
