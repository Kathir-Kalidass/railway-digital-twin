# Stage A2 (S0) — Multi-Train Block Signalling (Backend Extension) Design

Date: 2026-10-19  
Status: core modules implemented and tested; not yet wired into the live server (Phase 2 completion)
Parent design: [`2026-10-18-railway-digital-twin-enhancement-design.md`](./2026-10-18-railway-digital-twin-enhancement-design.md)  
Related designs: [`2026-10-19-stage-b-dashboard-design.md`](./2026-10-19-stage-b-dashboard-design.md), [`2026-10-19-stage-c-godot-digital-twin-design.md`](./2026-10-19-stage-c-godot-digital-twin-design.md), [`2026-10-19-stage-d-esp32-wokwi-design.md`](./2026-10-19-stage-d-esp32-wokwi-design.md), [`2026-10-19-stage-e-integrated-delivery-design.md`](./2026-10-19-stage-e-integrated-delivery-design.md), [`2026-10-21-stage-c2-double-track-multitrain-design.md`](./2026-10-21-stage-c2-double-track-multitrain-design.md)

> **Implementation note (2026-10-21):** `backend/src/railway.js`,
> `backend/src/signalling.js`, and `backend/src/simulation.js` implement the
> topology, aspect derivation, occupancy, and fixed-step train motion with
> passing tests. `state.snapshot()`, the live simulation loop, per-block MQTT
> topics/ACLs, station crossover/dwell behaviour, and the Godot/dashboard
> rendering are not yet wired. Phase 2 in the C2 design completes this contract.

> **Safety boundary:** This is an educational digital-twin simulation. The
> block/occupancy model, signal aspects, timetables, and stopping-distance
> figures are illustrative and are NOT certified railway signalling, train
> control, or safety equipment. Do not connect it to live signalling,
> infrastructure, or rolling stock.

## 1. Purpose and outcome

Extend the authoritative backend (Stage A) from a single aggregate "train"
and two hazard-only zone signals to a **multi-train, block-based signalling
model**, so the Godot digital twin (Stage C) and the dashboard (Stage B) can
render realistic operations: two running lines, block occupancy, meets at a
station, and layered signal aspects.

This is a **backend-owned authority expansion**. The backend remains the only
command/state/signal authority. Godot and the dashboard remain clients: Godot
renders authoritative state and publishes permitted sensor observations; the
dashboard issues authenticated REST controls.

Stage A2 is complete when the backend simulates N trains on a double-track
loop with blocks, derives per-block and per-zone aspects from occupancy and
existing hazards (most-restrictive wins), publishes the expanded state under
MQTT with least-privilege ACLs, exposes the multi-train REST surface, retires
the unauthenticated legacy simulation endpoint, and passes the expanded test
suite.

## 2. Scope and authority

### In scope

- A deterministic **train simulation loop** owned by the backend.
- A **double-track ring** topology with ordered **block sections** per line.
- A **station/loop** area with crossovers for meets and a scheduled dwell.
- **Layered signalling**: block occupancy + lookahead + existing zone hazard,
  most-restrictive wins; zone signal = most restrictive of its blocks.
- Expanded authoritative **state contract** (`trains[]`, `lines[]`, `blocks[]`,
  `station`, zone→blocks mapping).
- New/updated **MQTT topics** and **least-privilege ACLs**.
- Expanded **REST** surface (state already returns the new shape; add
  per-train speed control; retire the legacy endpoint).
- **Tests**: state/occupancy/aspect derivation, sim determinism, route
  contracts, ingest changes, ACL, integration.

### Out of scope

- Real interlocking, route-locking, or certified signalling.
- Timetabling beyond a simple repeating schedule per train.
- Junction complexity beyond the single station crossover set.
- TLS/production hardening (unchanged from Stage A/E).
- Godot rendering details (Stage C) and dashboard UI details (Stage B); this
  design only fixes the *contracts* they consume.

### Authority rules (unchanged, restated)

- The backend is the sole authority for trains, blocks, signals, state, and
  commands.
- Godot never publishes occupancy, state, signals, commands, events, or
  alerts, and never calls a REST control endpoint.
- The dashboard issues controls through authenticated REST only.
- Zone hazard behaviour from Stage A is preserved and **layered** with block
  occupancy; hazards can only make an aspect more restrictive, never less.

## 3. Domain model

### 3.1 Lines and blocks

Two running lines form a double-track **closed ring** (so trains circulate
continuously and meets occur naturally):

- `UP` and `DOWN` — each a closed loop of ordered **blocks**.
- Each block is a segment with a stable id and position along its line.

```text
block = {
  id:        string,          // e.g. "UP-B1" .. "UP-Bn", "DOWN-B1" .. "DOWN-Bn"
  line:      "UP" | "DOWN",
  index:     integer,         // 0-based order along the line
  zone:      "zone1" | "zone2",  // hazard-zone membership (layering)
  lengthM:   number,          // > 0
  occupiedBy: string | null   // train id currently occupying the block
}
```

- Block ids are stable and unique; ordering is by `index` within a `line`.
- `zone` maps each block into an existing hazard zone so wildlife/fault state
  can restrict it. Default: the first half of the ring is `zone1`, the second
  half `zone2`, with the mapping declared explicitly in config.

### 3.2 Station and crossovers

- One **station** occupies a designated block on each line (the "platform
  blocks") and declares a **crossover** pair connecting `UP` and `DOWN`.
- Trains on a meet schedule may dwell at the station platform block.
- Crossovers allow a train to change lines (used for the "passing/overtake"
  scenario). Crossover use is resolved by the authoritative simulation, not
  clients.

```text
station = {
  id:   "station",
  name: string,
  blocks: { UP: "UP-Bk", DOWN: "DOWN-Bj" },   // platform blocks
  crossovers: [ { id, from: "UP-Bk", to: "DOWN-Bj" }, { id, from: "DOWN-Bj", to: "UP-Bk" } ],
  dwellSec: number
}
```

### 3.3 Trains

```text
train = {
  id:            string,        // e.g. "T1"
  line:          "UP" | "DOWN",
  direction:     "UP" | "DOWN", // travel direction along the ring
  block:         string,        // current block id
  offsetM:       number,        // >=0, position within block
  speedKmh:      number,        // 0..80, simulated, authoritative
  targetSpeedKmh:number,        // 0..80, desired/commanded
  lengthM:       number,        // consist length
  status:        "RUNNING" | "DWELL" | "STOPPED" | "EMERGENCY",
  zone:          "zone1" | "zone2"   // derived from current block
}
```

- A train occupies one *or more* blocks if `lengthM` exceeds the current
  block length; occupancy is published for every block the consist overlaps.
- `speedKmh` is simulated by the backend; clients never set it directly (they
  set `targetSpeedKmh`).

## 4. Block and signalling model (layered)

For each block, an aspect is derived **only from backend state**:

1. **Hazard layer** — if the block's `zone` is restrictive
   (`wildlifeDetected || !sensorHealthy || status === 'RECOVERY_REQUIRED'`),
   the block aspect is `RED`.
2. **Occupancy layer** — signalling protects *ahead* of a train. For the
   signal guarding block `B`:
   - `RED` if the protected block (immediately ahead) is occupied;
   - `YELLOW` if a further-ahead block within the braking/lookahead window is
     occupied or restricted;
   - `GREEN` if the lookahead window is clear.
3. **Composition** — the block's published aspect is the **most restrictive**
   of (hazard layer, occupancy layer). Restrictiveness order:
   `GREEN < YELLOW < RED`.
4. **Zone signal** — a zone's published `signal` is the **most restrictive
   aspect among that zone's blocks**, and never less restrictive than the
   existing Stage A hazard result.

Lookahead window is a configurable number of blocks (default 2) sized to the
illustrative braking distance, not a certified distance.

This preserves Stage A behaviour (a hazard still yields `RED`) while adding
occupancy-driven `YELLOW`/`RED` on clear-hazard sections.

## 5. Simulation loop

- A **fixed-timestep** loop (default `tickMs = 500`) advances the world:
  - resolves each train's permitted target speed from
    `min(zone target, signal-derived limit, status limit)`, where a signal
    limit is `RED→0`, `YELLOW→caution (default 30 km/h)`, `GREEN→zone target`;
  - integrates speed toward the permitted target using the illustrative
    deceleration `2.0 m/s²` (braking) / `0.6 m/s²` (acceleration);
  - advances `offsetM` by `speed / 3.6 * dt`; on block boundary crossing it
    updates `block`, recomputes occupancy, and continues into the next block;
  - applies station dwell when a train reaches its platform block on schedule;
  - applies `EMERGENCY` (immediate full deceleration) when its zone becomes
    restrictive.
- The loop is **deterministic** for a given initial seed and tick count
  (integer tick counter drives any randomness; no wall-clock in the physics).
- Occupancy is recomputed from train extents every tick (authoritative), and
  is the source of truth for the occupancy layer in §4.
- The loop is disabled (or held) when `comm.mqttConnected === false`; on
  reconnect the backend reconciles and resumes without replaying stale ticks.
- The loop publishes a state snapshot on change and at a bounded heartbeat
  (default ≤ 2 Hz), matching the existing bus cadence.

## 6. State contract (authoritative)

`state.snapshot()` is extended (existing fields retained for compatibility):

```text
{
  zones: { zone1: Zone, zone2: Zone },   // existing fields, plus:
                                         //   zone.blocks: [blockId, ...]
                                         //   zone.signal: most-restrictive of blocks/hazard
  train:  Train | null,                  // DEPRECATED compatibility summary (primary train)
  trains: [ Train, ... ],                // authoritative multi-train list
  lines:  [ { id, blocks: [blockId, ...] }, ... ],
  blocks: [ Block, ... ],                // all blocks, ordered by line then index
  station: Station,
  comm:   { mqttConnected: boolean },
  overall: "NORMAL" | "RECOVERY_REQUIRED" | "HAZARD" | "SENSOR_FAULT" | "COMM_LOST",
  lastEvent: string,
  updatedAt: string                      // ISO-8601
}
```

- `train` is retained only so un-migrated clients do not break; it is derived
  from `trains[0]` and marked deprecated in code comments. It will be removed
  in a later cleanup once Stage B and Stage C have migrated.
- `zone.signal` and the retained `railway/zoneN/signal` topics keep their
  existing meaning but now reflect the layered/block result.
- `overall` derivation keeps Stage A precedence (`COMM_LOST` > `SENSOR_FAULT` >
  `HAZARD` > `RECOVERY_REQUIRED` > `NORMAL`), now considering all trains.

## 7. MQTT topics and ACL changes

### 7.1 Retained (backend → clients)

| Topic | Payload |
|---|---|
| `railway/state` | Expanded snapshot (§6), retained. |
| `railway/zoneN/signal` | Unchanged shape `{ zone, signal, timestamp }`, retained; value now layered. |
| `railway/signal/{blockId}` | **New** retained `{ block, line, zone, signal, timestamp }` per block. |

### 7.2 Simulation/telemetry (Godot → backend)

| Topic | Change |
|---|---|
| `railway/zoneN/wildlife` | **Unchanged** — Godot wildlife observation (allowed). |
| `railway/zoneN/train` | **Removed** — trains are now backend-authoritative. Godot must stop publishing it. |

### 7.3 ACL changes (`mosquitto/acl_file`)

- `user godot`: **remove** `topic write railway/zone1/train` and
  `topic write railway/zone2/train`; **add** `topic read railway/signal/+`
  (per-block signals). Keep wildlife write, commands/speed/signal reads.
- `user backend`: **remove** `topic read railway/zone1/train`,
  `railway/zone2/train`; **add** `topic write railway/signal/+`.
- `user dashboard`: **add** `topic read railway/signal/+` (retained per-block
  signals) alongside existing `railway/state`.
- No broad `railway/#` grants. Least privilege preserved.

## 8. REST surface changes

- `GET /api/state` — unchanged route; now returns the expanded shape (§6).
  `state:read` permission unchanged.
- `POST /api/speed` (existing Stage A control route) — extended to accept an
  optional `trainId`. When present and known, sets that train's
  `targetSpeedKmh`; otherwise applies the zone default (existing behaviour).
- `POST /api/control` (existing) — unchanged semantics; hazards/fault/reset
  remain zone-scoped.
- **`POST /api/event` (legacy, unauthenticated) — REMOVED.** This endpoint is
  an authentication bypass that applied `state.applyTelemetry`/`applyCommand`
  without auth, RBAC, replay, or audit. It is superseded by MQTT ingestion for
  device telemetry and by authenticated REST for control. Removing it is a
  security fix; the old Godot HTTP client is replaced in Stage C.

## 9. Ingestion changes

- `makeIngest.handle`:
  - **Remove** the `railway/zoneN/train` branch and `applyTelemetry` handling
    of `trainPresent`/`speedKmh` (trains are authoritative now).
  - **Keep** `railway/zoneN/wildlife` → `state.setWildlife(zone, bool)`.
  - **Keep** `railway/telemetry/esp32` handling, mapped to
    `state.setSensor(zone, healthy)`.
- `state.applyTelemetry` is split into narrow, validated setters:
  `setWildlife(zone, value)` and `setSensor(zone, value)`; the legacy merged
  telemetry setter is removed. Neither mutates train state.

## 10. Configuration

Extend `config`:

```text
trains: [ { id, line, direction, startBlock, startOffsetM, lengthM, schedule } , ... ]
blocks: { UP: [ { id, zone, lengthM }, ... ], DOWN: [ { id, zone, lengthM }, ... ] }
station: Station
tickMs: number          // default 500
lookaheadBlocks: number // default 2
cautionSpeedKmh: number // default 30
brakeMps2: number       // default 2.0
accelMps2: number       // default 0.6
```

Defaults define **4 trains** (2 UP, 2 DOWN), **5 blocks per line**, one
station with a crossover pair. All values are dev defaults; invalid config
fails fast at startup (validation errors, not silent fallback).

## 11. Ripple contracts

- **Stage B (dashboard):** add train list, block/occupancy diagram, per-block
  aspects, per-train speed control (role-gated). State read shape is §6.
- **Stage C (Godot):** render `trains[]`, `blocks[]`, `lines[]`, `station`,
  and per-block signals; stop publishing `railway/zoneN/train`; subscribe to
  `railway/signal/+` or read `railway/state`. Interpolate authoritative train
  motion; never authoritative.
- **Stage D (ESP32):** unaffected except that sensor telemetry now flows
  through `setSensor`; no contract change.
- **Stage E:** add S0 to the gate/demo matrix and the type of "block signalling
  / multi-train meet" demo step.

## 12. Verification and acceptance

### Automated checks

- **State/occupancy:** block occupancy from train extents; multi-block
  consists; boundary crossing; zone membership.
- **Aspect derivation:** hazard layer alone; occupancy layer alone; layered
  composition (most-restrictive wins); zone signal = most restrictive block;
  Stage A hazard precedence preserved.
- **Simulation:** deterministic given seed/tick count; speed integration
  clamps to `0..80`; `RED` holds a train; `YELLOW` cautions; `EMERGENCY` on
  zone-restrictive; station dwell.
- **Ingest:** `railway/zoneN/wildlife` and `railway/telemetry/esp32` still
  apply; `railway/zoneN/train` is ignored (no state change).
- **REST:** `/api/state` returns the expanded shape; `/api/speed` accepts
  optional `trainId` and rejects unknown ids with `400`; `/api/event` returns
  `404`.
- **ACL (`broker_acl.test.js`):** Godot denied publishing `railway/zoneN/train`
  and any state/command/signal write; allowed wildlife write and `signal/+`
  read. Backend allowed `signal/+` write. Dashboard allowed `signal/+` read.
- **Integration (`e2e.test.js`):** driven simulation produces meets; a hazard
  restricts the correct zone's blocks; a connect/disconnect cycle reconciles
  without replay.
- **Backend regression:** full `cd backend && npm test` passes.

### Acceptance

Stage A2 passes when all above automated checks pass with recorded evidence,
the ACL matrix reflects §7.3, `/api/event` is gone, and the expanded state is
published retained with per-block signals.

## 13. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Signalling realism creep | Keep an illustrative, config-bounded model; document it is not certified. |
| Determinism drift | Fixed tick, integer tick counter, no wall-clock in physics; property tests. |
| Analysis achieved: removing `/api/event` breaks a client | Stage C migrates Godot to MQTT in the same delivery; keep a deprecation note in README. |
| Expanded state breaks Stage B/C clients | Retain `train` as deprecated summary; vendor contract changes through Stage B/C specs. |
| Simulation loop load | Cap trains/blocks; publish at ≤2 Hz; recompute occupancy in O(trains). |
| Block/zone mapping ambiguity | Declare mapping explicitly in config; validate at startup. |
