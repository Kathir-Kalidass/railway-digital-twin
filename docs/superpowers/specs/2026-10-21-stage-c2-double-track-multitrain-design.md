# Stage C2 — Double Track, Track Interchange, and Multi-Train Meet/Pass Signalling

Date: 2026-10-21
Status: proposed
Parent design: [`2026-10-20-stage-c-libretrainsim-wildlife-design.md`](./2026-10-20-stage-c-libretrainsim-wildlife-design.md)
Related designs: [`2026-10-19-stage-a2-block-signalling-design.md`](./2026-10-19-stage-a2-block-signalling-design.md) (core modules only), [`2026-10-19-stage-b-dashboard-design.md`](./2026-10-19-stage-b-dashboard-design.md), [`2026-10-19-stage-d-esp32-wokwi-design.md`](./2026-10-19-stage-d-esp32-wokwi-design.md), [`2026-10-19-stage-e-integrated-delivery-design.md`](./2026-10-19-stage-e-integrated-delivery-design.md)

> **Safety boundary:** educational simulation only. The block/occupancy model,
> signal aspects, crossover routes, timetables, and stopping distances here are
> illustrative and are NOT certified railway signalling, interlocking, train
> control, or safety equipment. Do not connect this to live signalling,
> infrastructure, or rolling stock.

## 1. Purpose and outcome

Complete the deferred Phase 2 capability: two physical running lines, a station
crossover/track interchange, multiple trains, and block-based meet/pass
signalling that is authoritative in the backend and rendered in the Godot twin.

The backend already contains the Stage A2 pure modules
(`railway.js`, `signalling.js`, `simulation.js`) and passing unit tests, but the
live server still publishes the legacy single-train snapshot and never runs the
simulation. Phase 1 of the Godot twin has one local train on one 753.9822 m
loop. Phase 2 closes both gaps.

Phase 2 is complete when:

- the backend runs a deterministic multi-train simulation and publishes
  `trains[]`, `lines[]`, `blocks[]`, `station`, and per-block aspects;
- Godot renders two concentric tracks, the station and crossovers, block
  signals, and at least two moving trains from authoritative state;
- a scheduled meet/pass and an explicit crossover move are visible in the
  twin; and
- wildlife/stop authority still stops every train approaching the affected
  zone, with no client able to relax a backend safety decision.

## 2. Current baseline and gaps

| Area | Today | Gap for Phase 2 |
|---|---|---|
| Godot track | One loop, radius 120 m, length 753.9822 m | Inner DOWN loop, parallel alignment, wider corridor/structures |
| Godot trains | One local `LTSTrain` | Fleet of remote-controlled visual trains mapped from backend state |
| Godot signalling | Zone signal in HUD/reconciler | Per-block signal masts, station home signals, occupancy display |
| Backend topology | Pure `railway.js`, two lines × five blocks, four configured trains | Wire topology/trains into live state and the server tick |
| Backend aspects | Pure `deriveBlockAspects()`; occupancy layer tested | Publish aspects and per-block topics; compose with zone hazards |
| Station/crossover | Config fields only, no simulation use | Station dwell, crossover interlock, meet/pass routes |
| MQTT/ACL | Godot reads zone signal only; cannot read state/trains | Read-only fleet/block contract with least privilege |
| Dashboard | Single legacy `train` summary | Multi-train and block/occupancy view |
| Authority | Godot local motion; backend safety targets | Backend owns simulation/occupancy; Godot interpolates and renders |

The Stage A2 design remains the contract for block semantics. This C2 spec
adds the physical double-track/interchange model and the Godot integration,
and resolves the areas Stage A2 left open (line-specific lengths, crossover,
station dwell, live wiring).

## 3. Recommended architecture and key decisions

These are the recommended defaults for approval. Alternatives are listed in
§11.

### 3.1 Two concentric lines

- **UP** is the existing outer loop: radius `120.0 m`, length
  `753.9822 m`, centre at `(0, -120)`.
- **DOWN** is a new inner loop: radius `116.0 m`, length
  `2π × 116 = 728.8495 m`, same centre.
- Both loops start at the station at the top of the ring. The inner loop is
  offset by `4.0 m` laterally (`start_pos.z = -4.0`) so the station is shared
  and the two tracks stay parallel at a realistic spacing.
- The loops remain independent closed rings; a train changes lines only at the
  station crossover. There is no third track and no mid-loop junction in the
  first slice.
- Backend per-line block lengths become physical: five blocks per line, with
  lengths derived from each line’s circumference (`≈150.796 m` UP,
  `≈145.770 m` DOWN). The current uniform `blockLengthM: 300` no longer
  matches the visual world and must be replaced with per-line arrays.
- Zone mapping stays explicit per block. Default: first three blocks are
  `zone1`, last two are `zone2` on each line, preserving the current wildlife
  demo area.

### 3.2 Authority

- The **backend owns train positions, occupancy, and signal aspects** for this
  mode, because the demo is specifically about meet/pass/block signalling.
- Godot **interpolates** `(line, block, offsetM)` into smooth visual motion and
  renders the authoritative aspects. It does not decide routes or occupancy.
- The Phase 1 local wildlife fail-safe remains allowed to **tighten** a train’s
  target speed or stop it. It can never clear a backend hazard or grant a
  route.
- If the broker is disconnected, the twin holds the last safe state and does
  not invent clear signals or new routes. Local wildlife limits remain active.
- The dashboard remains REST-only for controls; Godot remains observation-only.

### 3.3 Station, crossovers, and interchange

- One station area at the top of the ring with an island platform between the
  two tracks and a footbridge.
- Two crossover routes connect the platform blocks:

```text
UP-B2   ── crossover A ──> DOWN-B2
DOWN-B2 ── crossover B ──> UP-B2
```

- A crossover is a mutually exclusive route: at most one train may occupy the
  crossover pair, and opposing moves are rejected. Approaching signals are RED
  while the route is set.
- The station platform block has a configurable dwell (`dwellSec`, default 20).
  A train stops at the platform, waits, then continues on its selected route.
- The visual switch is a short diagonal track segment between the two loops at
  the station. The train visually transitions between lines over that segment;
  the backend transition is atomic at block level.
- Phase 2 does not model facing-point derailment protection, track circuits, or
  real interlocking. It models only the illustrative mutual exclusion above.

### 3.4 Trains and demo scenario

Start with **two visible trains** for clarity:

- `T1`: UP/outer, consist length 60 m.
- `T3`: DOWN/inner, consist length 60 m.

The backend may keep the existing four-train config as an optional stress
scenario, but the default demo uses two so the meet is readable. A four-train
mode is enabled by config, not by a different code path.

Recommended scripted sequence:

1. Both trains run toward the station on their own lines.
2. Both stop at their platform blocks (“meet”).
3. T1 requests crossover A to DOWN; the route is granted only after T3 has
   cleared the platform block.
4. T1 dwells on DOWN while T3 departs; T2/T1 then passes on UP or DOWN as the
   scripted passing move.
5. T1 returns to UP via crossover B, and both trains resume the loop.

The exact passing order is a scripted scenario, not a general timetable solver.
Any config that would put two consists on the same block must fail validation
or be rejected by the route interlock.

## 4. Backend completion

### 4.1 Live state

Extend the authoritative snapshot without breaking the existing shape:

```text
{
  zones, train, comm, overall, lastEvent, updatedAt,   // retained
  trains: [ { id, line, direction, block, offsetM, speedKmh,
              targetSpeedKmh, lengthM, status, zone } ],
  lines: [ { id, blocks: [...] } ],
  blocks: [ { id, line, index, zone, lengthM, occupiedBy, signal } ],
  station: { id, name, blocks, crossovers, dwellSec },
  simulation: { tickMs, running, tick, lookaheadBlocks }
}
```

`train` stays as a deprecated compatibility summary derived from `trains[0]`.
No client may mutate the new fields.

### 4.2 Server loop

- Start the fixed-timestep simulation after MQTT is connected and the state is
  initialised.
- Each tick:
  1. validate/resolve routes and station dwell;
  2. compute occupancy from consist extents;
  3. derive per-block aspects with zone hazards;
  4. resolve each train’s permitted target (most restrictive);
  5. integrate speed/position;
  6. publish changed state and per-block signals.
- Use the existing `tickMs` (default 500), lookahead (2 blocks), caution 30 km/h,
  brake 2.0 m/s², accel 0.6 m/s².
- Pause/step-safe behaviour on reconnect; no replay of stale ticks.
- Deterministic for a fixed initial state and tick count. No wall-clock or
  unseeded randomness in motion.

### 4.3 Station/crossover implementation

Add a small `routes.js` or equivalent:

- `requestRoute(trainId, crossoverId)` validates train at platform block,
  direction, route free, and destination block free.
- `resolveDwell(train, station)` starts/ends the dwell.
- `applyCrossover(train, route)` changes `line`, `block`, and `offsetM`
  atomically and marks the crossover occupied until the train clears it.
- Route release occurs only when the train has fully left the crossover pair.
- Reject requests that would place two trains in one block, enter a crossover
  from both ends, or use a route while a hazard affects either endpoint.

### 4.4 MQTT, ACL, and REST

- Retain `railway/state`, but include the expanded fleet/topology shape.
- Publish `railway/signal/{blockId}` retained per block.
- Grant **read-only** `railway/state` and `railway/signal/+` to `godot` so it
  can render trains and signals. Godot must not publish state, occupancy, or
  routes.
- Keep wildlife write and command/speed/signal read permissions.
- `dashboard` reads state, events, alerts, and block signals.
- Remove the legacy unauthenticated `POST /api/event` path as part of this
  security cleanup; MQTT ingestion and authenticated REST are the supported
  paths.
- Extend `POST /api/speed` with optional `trainId`; reject unknown IDs.
- Do not add a broad `railway/#` ACL.

### 4.5 Tests

- Topology: per-line block lengths sum to the physical circumference; stable
  ids; zone mapping.
- Snapshot: `trains`, `lines`, `blocks`, `station`, legacy `train`.
- Simulation: occupancy, aspect layering, braking to RED, determinism.
- Crossover: one route at a time, reject double occupancy, release after clear,
  station dwell, scripted meet/pass.
- Hazards: wildlife in `zone1` stops both trains approaching that zone and
  never clears until reset.
- Broker: ACL matrix, retained per-block signals, no Godot publish of state.
- REST/RBAC: per-train speed authorisation and validation.

## 5. Godot completion

### 5.1 Track and world geometry

- Add `InnerTrack` (DOWN, radius 116 m) under the same `World` node, with
  `track_line = "DOWN"` metadata and its own `LTSTrack` visuals.
- Keep the outer UP track as the existing `Track`; add a `TrackRegistry` that
  maps `UP`/`DOWN` to the correct rail and exposes physical lengths.
- Offset the inner loop’s start so the station platform sits between the two
  tracks; verify the 4 m spacing at the station, bridges, and crossing.
- Widen the terrain/flatten corridor, catenary, ballast, and tree exclusion to
  cover both tracks.
- River: add a railway bridge for the inner line at its corresponding river
  crossings. Keep the road bridge and two outer railway bridges; resulting
  geometry has four railway bridge decks (two pairs) or two widened decks — the
  implementation must not leave unsupported rails.
- Level crossing: cover both tracks with one road pad and a barrier set for
  each track/approach. The crossing point API returns both track points so the
  wildlife hazard can stop both lines.
- Station: island platform, two platform edges, footbridge/stairs, platform
  lamps, signs, and a visible crossover pair with switch blades.

### 5.2 Fleet rendering

Add a `FleetController` / `RemoteTrain` layer:

- Subscribe to the expanded `railway/state` (read-only).
- For each backend train, create/update a visual consist on the mapped line.
- Convert `(block, index, offsetM)` to a physical track distance:
  `distance = sum(line block lengths before index) + offsetM`.
- Interpolate distance, heading, and speed smoothly rather than snapping on
  every 500 ms snapshot.
- Keep each train’s existing `LTSTrain` visual/consist machinery where possible;
  separate the visual pose from local authority.
- On a crossover transition, interpolate across the diagonal segment over a
  short duration and animate the switch blades; do not teleport.
- If a train disappears from state, remove its visual safely; never leave a
  ghost consist occupying a block.

The local wildlife path continues to apply to all relevant trains: a stop in
the hazard zone must stop every train whose route enters it, not only the
camera-selected train. The per-train target is `min(backend target, local
wildlife limit)`.

### 5.3 Signals and HUD

- Add a signal mast at each block boundary on both lines, plus station home
  signals. Aspect colours: GREEN, YELLOW, RED, with a small block-id label.
- Drive aspects from retained per-block topics or the snapshot; do not derive
  authoritative aspects locally.
- Extend the HUD: selected train id, line, block, speed/target, block aspect,
  route/crossover state, and fleet count.
- Add a train selector and a meet camera. Follow/cab/drone must target the
  selected train; the drone should be able to frame the station meet.
- Add a scripted `meet` scenario that requests the crossover through the
  backend/API and plays the camera sequence; do not fake the route locally.

### 5.4 Tests and captures

- Parse/load tests for the inner track, bridge pairs, station, crossing, and
  signal masts.
- Geometry tests: 4 m spacing at the station, both tracks flattened, all rails
  supported over the river, crossing pad covers both tracks.
- Fleet mapping tests: block/offset conversion for both lines, wraparound,
  interpolation without snapping, crossover transition.
- Signal tests: per-block aspect rendering and station home aspects.
- Meet scenario test: scripted route grant/reject, dwell, pass, resume.
- Wildlife fleet test: a hazard stops both approaching trains.
- Visual capture: double-track overview, station meet, crossover, signal
  aspects, and the existing wildlife shot.

## 6. Delivery slices

| Slice | Contents | Exit criterion |
|---|---|---|
| 2A — backend live | Wire topology, state, loop, aspects, per-block topics/ACL, tests | Backend publishes multi-train state; existing Godot still runs |
| 2B — double-track world | Inner loop, widened corridor, station, bridges, crossing, statics | Both loops render with no unsupported track or terrain gaps |
| 2C — fleet render | Remote trains, interpolation, HUD selector, signal masts | Two trains visibly run authoritative positions and aspects |
| 2D — interchange/meet | Crossover routes, station dwell, meet/pass script, cameras | Scripted meet/pass completes with no block overlap |
| 2E — integration | Wildlife affects both lines, dashboard, ESP32 unaffected, docs/captures | Acceptance matrix and visual demo pass |

Each slice must keep the full existing suite green. Do not land 2A in a state
where the current single-train scene cannot start.

## 7. Acceptance criteria

1. Backend: deterministic multi-train simulation; no block ever reports two
   occupying consists; every train respects RED; all existing 58 tests pass
   plus the new C2 tests.
2. Crossover: at most one grant at a time; a second request while occupied is
   rejected; a route is released after the consist clears; a hazard rejects or
   holds the route.
3. Station: both trains dwell at the platform and then proceed; the meet/pass
   scenario completes and returns to normal running.
4. Godot: two concentric tracks, four railway bridge decks (or two verified
   widened decks), one two-track level crossing, island platform, visible
   crossover blades, per-block signals, and two moving trains.
5. Wildlife: an animal on the crossing forces both affected trains to stop;
   after the animal clears and the backend resets, both resume; a disconnected
   broker cannot produce a false clear.
6. Dashboard: shows the fleet, blocks, occupancy, and aspects; per-train speed
   control is role-gated.
7. Evidence: Godot suite passes (existing 15 + new C2 suites); backend suite
   passes; GPU captures include double-track overview, meet, crossover, and
   wildlife; Windows checklist updated.

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Inner/outer circumference mismatch breaks backend block math | Per-line block-length arrays and a geometry test; reject configs whose lengths do not sum to the line circumference |
| Crossover teleports or clips through the other train | Interpolate over a short segment; route mutual exclusion; visual occupancy check in tests |
| Godot local safety fights backend targets | One fleet reconciler that always takes the minimum; local can only tighten |
| Two trains overlap visually due snapshot cadence | Interpolate from last snapshot, clamp to block extents, and test no-overlap invariant |
| Wildlife crossing only stops one line | Crossing exposes both track points; hazard snapshot includes both lines; fleet stop test |
| Bridge/terrain gaps at the second track | Geometry tests plus GPU overview capture |
| Scope creep into real interlocking | Explicitly out of scope; only illustrative route mutual exclusion |

## 9. Open decisions for approval

1. **Default train count:** two visible trains (recommended) vs four-train
   stress mode. The backend may support four behind config either way.
2. **Station platform:** island between tracks (recommended) vs two side
   platforms. Island keeps the station compact; side platforms simplify
   building placement.
3. **Crossover count:** one pair at the station (recommended for Phase 2) vs an
   additional mid-loop pair. A second pair increases scenic and interlocking
   complexity.
4. **Legacy endpoint removal:** confirm that removing `POST /api/event` in the
   same slice is acceptable. It is a security fix but changes an existing
   endpoint.
5. **Track spacing:** 4.0 m centre-to-centre (recommended, visually plausible
   for the scale) vs a wider 5–6 m spacing if the train models clip at the
   station.

## 10. Explicitly out of scope

- Real interlocking, route locking, track circuits, axle counters, or AWS/ATP.
- Facing-point protection, derailers, and real switch machines.
- General timetable optimisation or arbitrary route planning.
- A third track, yard, or freight operations.
- TLS/production provisioning and certified stopping-distance claims.
- Replacing the Phase 1 wildlife behaviour with a full navigation graph.

## 11. Alternatives considered

- **Keep one track and fake a second visually.** Rejected: the user explicitly
  asked for two tracks, an interchange, and a visible meet.
- **Keep train motion entirely local in Godot.** Rejected for this mode:
  multi-train safety and occupancy would then be a client decision and would
  diverge from the documented backend authority.
- **Implement the full LTS switch/route system.** Rejected for Phase 2: the
  ported LTS runtime is large and editor-oriented; the required station
  crossover can be modelled with an explicit route table and short visual
  transition while preserving the blocking contract.
- **Use the existing Stage A2 topology unchanged at 300 m blocks.** Rejected:
  five 300 m blocks would not match the 754 m visual loop, making speeds,
  stopping distances, and meet positions misleading.
