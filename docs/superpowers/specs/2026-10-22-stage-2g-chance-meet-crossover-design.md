# Stage 2G — Chance-Based Meet Crossover (Design)

**Status:** approved for implementation (2026-10-22)
**Prerequisites:** Stage C2 slices 2B–2E complete (double-track world, fleet rendering, meet/pass, integrated delivery) and Stage 2F complete (wildlife sensing). This spec extends C2 and must not break its exit gates.
**Related:**
- `docs/superpowers/specs/2026-10-21-stage-c2-double-track-multitrain-design.md` (§3.3 station crossovers, §3.4 demo scenario, §4.2 live state, §4.3 routes)
- `docs/superpowers/specs/2026-10-22-stage-2f-distributed-wildlife-sensing-design.md` (deferred 2G to this spec)

## 1. Goal

Replace the fixed, client-scripted meet sequence (`scenario_director.gd:53-137`) with a **backend-authoritative, randomised meet scheduler**:

1. Meets happen at randomised intervals instead of a fixed script.
2. One train holds at its platform block while the opposite train keeps moving through the station, then resumes.
3. With configurable probability the holding train crosses to the other line via a station crossover (`X-UP-DOWN` / `X-DOWN-UP`) once the route is safely available.
4. Every random decision is driven by one seeded PRNG so a run is reproducible for debugging; changing the seed changes the sequence.
5. The scheduler uses the existing route interlock and simulation loop; it never bypasses safety checks.

**Non-goals:** a general timetable solver; new crossover locations (the only valid routes are the two station crossovers); sensor/camera power management (the "auto-off" item was clarified as automatic train slowdown and is covered by 2F/onboard braking).

## 2. Safety principles (binding)

1. **Backend authoritative.** Holds are applied as `train.commandedSpeedKmh = 0` on the authoritative train record. Godot only renders. No client may request or cancel a hold.
2. **Route interlock is the only grant path.** Every crossover request goes through `routes.requestRoute`, which checks train position, route exclusivity, destination occupancy, restrictive zones, and active hazards. The scheduler adds no shortcut.
3. **Resume only when permitted.** A hold is released only when the hold timer has expired, the train's current block has no active hazard, and (for a crossover meet) the route has been released by the interlock.
4. **No two trains in one block.** The scheduler never requests a route whose destination block is occupied; the interlock rejects it anyway. The block-occupancy invariant is asserted in tests for every tick.
5. **Stop beats chance.** If a precondition fails, the scheduler skips the meet and returns to `IDLE`. It never forces a route.
6. **Deterministic randomness.** All randomness comes from one seeded PRNG advanced only on scheduler transitions. No wall-clock or `Math.random()` in scheduler decisions. A fixed seed and tick sequence reproduce the same meet history.
7. **Fail-safe coupling.** Active hazards or restrictive zones suppress holds/crossovers; 2F's local wildlife limits still tighten speed independently.

## 3. Architecture

```
state.tick(dtSec)
  ├─ meetScheduler.tick(dtSec)          backend/src/meets.js
  │    phases: IDLE → WAITING → HOLDING → (optional CROSSING) → IDLE
  │    holds via train.commandedSpeedKmh
  │    crossover via routes.requestRoute()
  ├─ routes.tick()                       existing release logic
  └─ stepTrains(...)                     existing motion
fleetSnapshot() → state.meets = meetScheduler.snapshot()
        │
railway/state (MQTT)
        ├─ Godot FleetController (existing) + TwinHUD meet line (new)
        └─ React dashboard meet card (new)

POST /api/meet        { enabled?, seed?, trigger? }   (operator, route:set)
```

The scheduler sits beside `stepTrains`; it only issues speed commands and route requests, never direct block or pose writes (the route interlock performs the atomic line/block transition).

## 4. Interfaces

### 4.1 Config (`backend/src/config.js`)

```js
meets: {
  enabled: true,
  seed: Number(process.env.MEET_SEED || 20261022),
  minGapSec: 60,          // gap between meet opportunities
  maxGapSec: 180,
  stationWaitSec: 90,     // give up if the station window is never reached
  minHoldSec: 6,
  maxHoldSec: 15,
  meetChance: 0.8,        // chance a scheduled opportunity becomes a meet
  crossoverChance: 0.5,   // chance a meet includes a crossover
  holdTimeoutSec: 25      // longest the holder waits for a safe route
}
```

`MEETS_ENABLED=0` disables the scheduler entirely (fixed-loop behaviour). `validateConfig` rejects gaps with `min > max`, probabilities outside `0..1`, and unknown station blocks.

### 4.2 Scheduler API (`backend/src/meets.js`)

```js
makeMeetScheduler({ topology, trains, zones, routes, hasActiveHazard, config, seed })
// returns { tick(dtSec), snapshot(), setEnabled(bool), setSeed(number), trigger() }
```

Supported station blocks come from `topology.station.blocks` (`{ UP: 'UP-B2', DOWN: 'DOWN-B2' }`).

Phase behaviour:

| Phase | Behaviour | Exit |
|---|---|---|
| `IDLE` | Count down `nextGapSec` sampled from `[minGapSec, maxGapSec]`. `trigger()` skips the countdown. | Countdown done → `WAITING` |
| `WAITING` | Wait until at least one train is in its station block and the other is within the station approach window (its station block or the block immediately before). Roll `meetChance`; on failure or `stationWaitSec` timeout reschedule and return to `IDLE`. | Window met + chance passes → `HOLDING` |
| `HOLDING` | Holder = the train at its station block (if both, pick 50/50 by PRNG). Applied `commandedSpeedKmh = 0`; the other train is untouched. Sample hold duration in `[minHoldSec, maxHoldSec]`. If `crossover` was sampled, request the holder's route as soon as the destination block is free; rejected requests retry each tick. | Hold timer expired and no hazard on the holder's block and (if crossing) route granted → `CROSSING` or release → `IDLE`; timeout → release, skip, `IDLE` |
| `CROSSING` | Route granted; hold released. Wait for `routes` to release the route (the train has cleared the destination block). | Route released → `IDLE` with a new gap |

Hold release restores the train's previous `commandedSpeedKmh` (which may be `null`).

### 4.3 Snapshot (`state.meets`)

```json
{
  "enabled": true,
  "seed": 20261022,
  "phase": "HOLDING",
  "nextMeetInSec": 0,
  "config": { "meetChance": 0.8, "crossoverChance": 0.5 },
  "active": {
    "tick": 1234,
    "holderId": "T3",
    "holdRemainingSec": 7.5,
    "crossover": true,
    "routeId": "X-DOWN-UP"
  },
  "last": {
    "tick": 900, "holderId": "T1", "otherId": "T3",
    "crossed": true, "routeId": "X-UP-DOWN", "outcome": "COMPLETED"
  },
  "history": [ { "tick": 1234, "holderId": "T3", "crossed": false, "outcome": "HELD" } ]
}
```

`outcome` is one of `HELD`, `COMPLETED`, `SKIPPED`, `SAFETY_HELD`. `history` keeps the last 10 entries, oldest first.

### 4.4 REST

`POST /api/meet` — permission `route:set` (operator/admin), replay-deduplicated request id, audit record action `MEET`.

```json
{ "request_id": "uuid", "enabled": true, "seed": 42, "trigger": false }
```

Response: `{ "ok": true, "state": <snapshot> }`. Validation errors → 400, RBAC → 403, replay duplicate → 400. `enabled`/`seed` are optional; `trigger: true` arms the next station window immediately.

### 4.5 Godot

- `FleetController` already applies `trains`; no motion changes.
- `TwinHUD` subscribes to `railway/state` (it currently does not), stores `meets`, and shows `MEET <phase>` with holder/route/countdown in the metrics line. The HUD falls back silently when `meets` is absent (backward compatible with older snapshots).
- `ScenarioDirector.run_meet_scenario` remains available as an offline demo but is no longer the authoritative meet behaviour.

### 4.6 Web dashboard

The React dashboard adds a **Meet schedule** card: enabled state, phase, countdown to next meet, active holder/crossover/route, and the last outcome. Values come from `state.meets`; no new API is required for display.

## 5. Tests

- `backend/test/meets.test.js`
  - same seed + same tick sequence ⇒ identical history (holder ids, crossover flags, route ids, tick numbers);
  - different seeds ⇒ at least one differing decision in a bounded run;
  - hold sets the holder's `commandedSpeedKmh = 0` while the other train's target stays > 0;
  - route is only requested for a train in its station block, never when the destination is occupied, hazardous, or restrictive;
  - release happens only after hold expiry and with no active hazard on the holder's block;
  - disabled ⇒ phase stays `IDLE`, no holds, simulation unchanged;
  - `trigger()` starts a meet at the next station window;
  - block-occupancy invariant (no block with two trains) holds on every tick.
- `backend/test/control_routes.test.js` additions: `/api/meet` auth, RBAC, validation, replay, audit.
- `godot/tests/test_meet_hud.gd`: HUD shows phase/holder from a `railway/state` payload and tolerates a missing `meets` key.
- Full regression: Godot, backend, ESP32 native, web build.

## 6. Acceptance criteria

1. With two trains and `meets.enabled`, a randomised meet occurs within `maxGapSec`; one train holds while the opposite train keeps moving.
2. Crossover meets occur with approximately `crossoverChance` frequency, only through `X-UP-DOWN` / `X-DOWN-UP`, and only when the interlock grants the route.
3. The same seed reproduces the same meet sequence; a different seed changes it.
4. No tick ever places two trains in one block; no route is granted across an active hazard or restrictive zone.
5. Disabled mode reproduces the pre-2G fixed-loop behaviour exactly.
6. Godot HUD and the web dashboard display the live meet phase from `state.meets`.
