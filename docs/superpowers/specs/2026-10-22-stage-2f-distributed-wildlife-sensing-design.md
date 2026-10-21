# Stage 2F — Distributed Wildlife Sensing and Onboard Camera Detection (Design)

**Status:** approved for implementation (2026-10-22)
**Prerequisites:** Stage C2 slices 2B–2E complete (double-track world, fleet rendering, meet/pass, integrated delivery). This spec extends C2 and must not break its exit gates.
**Deferred:** Stage 2G (chance-based meet crossover) is out of scope here and gets its own spec.
**Related:**
- `docs/superpowers/specs/2026-10-21-stage-c2-double-track-multitrain-design.md` (zones, blocks, trains T1/T3, crossovers)
- `docs/superpowers/specs/2026-10-20-stage-c-libretrainsim-wildlife-design.md` (animal visuals, publisher, safety controller)

## 1. Goal

Replace the single scripted wildlife event at a fixed level crossing (distance 260 m, `world_wildlife.tscn:76`, `wildlife_behaviour.gd:54-81`) with:

1. **Distributed trackside sensing** — ten visible sensor huts (five per loop, at block boundaries) that detect animals anywhere between them and report block-scoped observations to the backend.
2. **Random animal appearances** — proximity-triggered events at random points 80–280 m ahead of an approaching train, on either loop.
3. **Onboard camera detection** — a forward-facing camera on each train running a deterministic simulated-ML detector, giving a stop path that never depends on MQTT or the backend.
4. **Block-scoped hazards with evidence** — trackside and onboard observations are separate evidence on a shared hazard record; either can initiate protection; clearing requires all evidence clear plus the existing authorized reset.

Educational simulation only. Nothing here is certified railway signalling or safety equipment, and the "ML" detector is a deterministic simulation with a documented swap point for a real ONNX/TFLite model.

## 2. Safety principles (binding)

1. **Either detection path can initiate a stop independently.** Trackside path: sensor → backend hazard → block RED → train control. Onboard path: local braking immediately, with no network dependency.
2. **A train must never wait on MQTT or backend response time to begin braking.** Onboard detection calls `TrainReconciler.set_local_wildlife_limit(0)` directly.
3. **The backend coordinates network-wide protection; each train enforces its own braking.** A hazard in one block must not stop the other train unless that train's route or protected stopping distance is affected.
4. **Evidence is per source and per block.** A trackside clear must not clear an onboard observation (or vice versa). The hazard record clears only when all active evidence clears, then transitions through `RECOVERY_REQUIRED` and requires the existing authorized `RESET`.
5. **Observations carry unique IDs; duplicates are dropped and stale observations rejected.**
6. **The camera follows the train's actual direction of travel** (route/transform), never a hard-coded world direction or merely the sign of speed.

## 3. Architecture

```
Path A — trackside                    Path B — onboard
10 sensor huts (5 per loop)           per-train Camera3D + SimulatedAnimalDetector
Area3D coverage, 75 m                 forward cone ±25°, 180 m, occlusion, confidence
        |                                      |
railway/wildlife (MQTT)                local stop request (no network)
        |                                      |
        v                                      v
backend safety supervisor              train braking controller (local)
 block hazard + evidence                       |
 approach caution                              |
 route protection                              |
        |                                      |
railway/signal/<block> (retained)      publish onboard observation
railway/commands/esp32 (backend)       railway/wildlife (MQTT)
        |                                      |
        v                                      v
      ESP32 outputs                        dashboard / backend evidence
   red light, buzzer, barrier
```

`WildlifeDirector` owns scenario generation and animal movement only. It never decides whether the railway is safe; the sensors and camera independently observe the simulated animals.

## 4. Interfaces

### 4.1 MQTT — new block-scoped wildlife topic

New topic `railway/wildlife` (godot publishes; backend subscribes; ACL updated). The legacy zone topic `railway/<zone>/wildlife` remains for backward compatibility and existing tests; the twin's new sensing paths use `railway/wildlife` exclusively.

Payload:

```json
{
  "eventId": "trackside-UP-S2-1729591200.1",
  "source": "trackside",            // "trackside" | "onboard-camera"
  "line": "UP",                     // "UP" | "DOWN"
  "distanceM": 312.4,               // animal's track distance on that line (the event crossing point)
  "wildlifeDetected": true,
  "species": "deer",                // "deer" | "elephant" | "wildlife"
  "count": 1,
  "onTrack": true,
  "sensorId": "UP-S2",              // trackside only
  "trainId": "T1",                  // onboard-camera only
  "confidence": 0.82,               // onboard-camera only, 0..1
  "timestamp": 1729591200.1         // unix seconds or ISO-8601
}
```

Validation (reject → `INVALID_WILDLIFE` event, no state change):
- `source` in `{trackside, onboard-camera}`; `line` in `{UP, DOWN}`; `wildlifeDetected` boolean (required).
- `eventId` non-empty string; duplicate `eventId` dropped (LRU 256, same pattern as telemetry `request_id`).
- `timestamp` parseable (unix seconds or ISO) and within ±30 s; older observations rejected as stale.
- `distanceM` finite, `0 ≤ distanceM < lineLengthM[line]`; `count` non-negative integer; `confidence` optional number in `0..1` (required for `onboard-camera`).
- `sensorId` required for `trackside`, `trainId` required for `onboard-camera`.
- `onTrack` is true while the reporting source's covered animal set is non-empty (same meaning as the legacy detection band).

Block resolution (backend, authoritative): `index = floor(distanceM / (lineLengthM[line] / blocksPerLine)) % blocksPerLine` with `blocksPerLine: 5` → block id `${line}-B${index}`. Godot never sends block IDs; it sends `line` + `distanceM`.

### 4.2 Backend state — block hazard with evidence

New state record per block:

```js
blockHazards: {
  "UP-B2": {
    blockId: "UP-B2", line: "UP", zone: "zone1",
    evidence: {
      trackside: { active: true,  sensorId: "UP-S2", species: "deer",      eventId: "…", at: 1729591200100 } | null,
      onboard:   { active: false, trainId:  "T1",    species: "deer", confidence: 0.82, eventId: "…", at: 1729591200100 } | null
    },
    active: true          // derived: any evidence active
  }
}
```

Transitions:
- Any observation with a resolved block sets that source's evidence (`active` = `wildlifeDetected`, updating `at`/`eventId` detail).
- `active` = OR of evidence active flags. Hazard acts only while `active` is true.
- When `active` goes false (all evidence cleared): block hazard enters recovery; the block's zone status becomes `RECOVERY_REQUIRED` (restrictive) and requires the existing `RESET` (which still only succeeds with no active hazards and healthy sensors). A clear observation for one source never clears the other source's evidence.

Snapshot additions (`/api/state`, retained `railway/state`):
- `blocks[].hazard`: `null`, or for an active hazard `{ sources: ["trackside","onboard"], since }` (only active evidence sources are listed).
- `zones[z].blockHazards`: array of active hazard block IDs in that zone.
- `overall`: `HAZARD` while any evidence is active (composed with existing `COMM_LOST`/`SENSOR_FAULT` precedence unchanged).

Signalling composition (`deriveBlockAspects`):
- Active hazard block → `RED` (prohibit entry).
- Previous block on the line (`(index - 1 + n) % n`) → at least `YELLOW` (approach caution).
- Other blocks unaffected by the hazard; existing occupancy and legacy zone-restrictive folding unchanged.
- `zoneSignal`: unchanged for legacy zone hazards (restrictive zone → `RED`); a block hazard alone makes the zone signal `YELLOW` (informational), not `RED`, so the unaffected train keeps running. `RECOVERY_REQUIRED` remains restrictive and yields `RED` as today.

Routes (`routes.js`): a route grant is rejected when any block traversed by the route (including crossover legs) has an active hazard, in addition to the existing endpoint-zone restriction check.

### 4.3 Backend → ESP32 alert

When the first evidence activates in a block whose `zone === config.esp32Zone`, the backend publishes a command to `railway/commands/esp32`:

```json
{
  "request_id": "backend-wildlife-<n>",
  "zone": "zone1",
  "event": "WILDLIFE_DETECTED",
  "timestamp": "<ISO>",
  "source": "backend",
  "payload": { "blockId": "UP-B2", "line": "UP", "source": "trackside" }
}
```

When the last evidence in `esp32Zone` clears: same envelope with `WILDLIFE_CLEARED`. Edge-triggered, non-retained, deduplicated by the backend (one rising edge per hazard episode).

ESP32 firmware change: `onMqttMessage` accepts `source` `"dashboard"` or `"backend"` for `WILDLIFE_DETECTED`/`WILDLIFE_CLEARED` (all other commands still require `"dashboard"`). Output mapping reuses the existing `WILDLIFE_SET`/`WILDLIFE_CLEAR` effects → red LED, buzzer, barrier 90°. Comm-loss behaviour is unchanged (`backendContextFresh` false → restrictive). The ESP32 remains a zone-level indicator in this stage; block identity is carried in `payload` but rendered only in the command log/status as available.

### 4.4 Godot — sensor huts

Node `SensorHuts` under `WorldWildlife`, built by `wildlife_sensor_network.gd` using `TrackRegistry` tracks:

- One hut per block boundary per loop: distances `k * lineLength / 5` for `k in 0..4`; ids `UP-S0..UP-S4`, `DOWN-S0..DOWN-S4` (10 total). Each hut is a visible small equipment building (box hut, post, antenna, indicator lamp) with `line` and `boundary_distance_m` metadata.
- Each hut owns an `Area3D` cylinder of radius `sensor_coverage_m` (default 75 m) monitoring animals in group `wildlife`.
- On change of the set of covered animals, the hut publishes to `railway/wildlife` with `source: "trackside"`, its `sensorId`, the `line`, `distanceM` = the event crossing distance of the nearest covered animal (animal meta `track_distance_m`), `species`, `count`, `onTrack`, a unique `eventId`, and `timestamp`. Empty set publishes a clear (`wildlifeDetected: false`, `count: 0`).
- Coverage is continuous along a loop: adjacent 75 m radii overlap (block length ≈ 151 m / 146 m).

### 4.5 Godot — WildlifeDirector

New `WildlifeDirector` node replaces the fixed-crossing event logic:

- Tracks each active train's line and track distance (local `LTSTrain` position in single-train mode; backend fleet state when fleet rendering is active).
- Proximity trigger per train: while cooldown is inactive, when a train is running, pick a random point `uniform(80, 280) m` ahead of that train on its line (wrapping), then spawn 1–2 animals (random species: deer/elephant) at that point, crossing perpendicular to the rails and leaving on the far side. Cooldown `uniform(30, 60) s` after each event.
- Deterministic: exports `seed` (default `20261022`); with fixed simulation steps the same seed produces the identical event sequence of `(train, distanceM, species, count)` (test requirement 9).
- Train positions come from a `train_provider` interface: the local `LTSTrain` in single-train mode, or the fleet controller's rendered trains when fleet mode is active. Tests force the local provider.
- The existing manual triggers (Space key, ESP32 telemetry rising edge, scenario reel) call the same random-point event path; the legacy fixed crossing at 260 m remains scenery and can coincidentally be a crossing point, but is no longer the default or the only location.
- Animal movement is the existing walk-cross-dwell-walk-out behaviour, parameterised by the event's crossing point and direction instead of the single `LevelCrossing`. Each animal carries `line` and `track_distance_m` metadata for the huts.

### 4.6 Godot — onboard camera and detector

Per train (`T1`, `T3`):

- **Camera:** `Camera3D` attached to the first runtime carriage (`Train/Locomotive`, created by `ltstrain.gd`; in fleet mode, the lead carriage of each rendered train) at the cab front (`+X` carriage-forward, headlight end), oriented `look_at(carriage.global_position + forward * N, up)`. Camera orientation follows the carriage's global basis, so it rotates with the track tangent on curves and follows the route direction — not the sign of speed.
- **Detector:** `SimulatedAnimalDetector` implements the `AnimalDetector` abstract class (`animal_detector.gd`):

```gdscript
func detect(snapshot: Dictionary) -> Array[Dictionary]
# snapshot: { camera_transform: Transform3D, speed_kmh: float,
#             animals: [{ position: Vector3, species: String }] }
# returns:  [{ species: String, confidence: float, distance_m: float,
#              screen_position: Vector2 }]   # screen_position in 0..1 viewport coords
```

The default `SimulatedAnimalDetector` evaluates every `camera_interval_ticks` (default 3) and reports an animal when:
1. it is within `camera_range_m` (default 180 m) ahead along the camera forward axis (±`camera_cone_deg` = ±25° horizontally, ±`camera_vertical_cone_deg` = ±10° vertically), and
2. the sight line is not occluded — deterministic analytic occlusion: terrain height sampling via `TerrainGenerator.height_at` along the sight line (terrain blocks if the terrain profile rises above the eye line), tree cylinders from `SceneryDirector.tree_roots()` (radius 1.2 m, height 8 m), and bridge deck/parapet AABBs for `RailwayBridgeA/B`.
3. `confidence = clamp01((1 − distance_m / camera_range_m) * species_visibility)` with `species_visibility` deer 0.9, elephant 1.1; a detection is “positive” when `confidence ≥ min_confidence` (default 0.65).

`AnimalDetector` is independent of rendering; headless tests call `detect()` with synthetic snapshots and assert range, cone, occlusion, confidence thresholds.

- **Debounce:** protection reacts on `detection_persistence` (default 2) consecutive positive evaluations, except a *critical* detection (animal within `d_stop(current speed)`, where `d_stop` already includes the margin) which acts on the first positive evaluation.
- **Local braking:** on positive detection the detector calls `TrainReconciler.set_local_wildlife_limit(0)` immediately (existing API, no MQTT). Clearance lifts the limit only after `detection_clear_hold_s` (default 3 s) without positives. The camera path also imposes a speed restriction when the remaining detection distance is insufficient for the current speed (section 5).
- **Onboard observation:** each false→true transition publishes one observation to `railway/wildlife` (`source: "onboard-camera"`, `trainId`, `line`, `distanceM` = `(train distance + detection distance) % lineLength`, `confidence`, unique `eventId`), and one clear on true→false. Network failure must not affect braking.
- **HUD:** the status line gains a camera indicator (`CAM clear` / `CAM detect 0.82`), replacing nothing else.

## 5. Stopping-distance model (binding for local braking)

```
d_stop(v) = v * t_latency + v² / (2 * a) + d_margin
```

- `v` m/s, `t_latency` default 0.6 s (detection interval plus processing), `a = brakeMps2` from backend config (2.0 m/s²), `d_margin` default 25 m.
- If `d_stop(v) > distance_to_detection`, the train must not continue at `v`; the braking controller requests a stop (limit 0) rather than relying on the 180 m camera range.
- If `d_stop(v)` approaches the camera range, the onboard controller applies a speed restriction through the reconciler's local limit so the train slows before the detection window ends.
- Implemented as a pure function (`onboard_braking.gd`) with unit tests; parameters are exported simulation defaults, not validated real-world limits.

## 6. Simulation parameters (defaults; all exported/configurable)

| Parameter | Default | Notes |
|---|---|---|
| Trackside sensor huts | 10 | 5 boundaries × 2 loops |
| `sensor_coverage_m` | 75 | initial coverage radius |
| `camera_range_m` | 180 | maximum look-ahead |
| `camera_cone_deg` | ±25 | horizontal |
| `camera_interval_ticks` | 3 | detector cadence |
| `min_confidence` | 0.65 | simulated threshold |
| `detection_persistence` | 2 | consecutive positives; critical = 1 |
| Wildlife spawn window | 80–280 m ahead | per train |
| Wildlife cooldown | 30–60 s | randomised |
| `t_latency` / `d_margin` | 0.6 s / 25 m | stopping-distance model |
| `detection_clear_hold_s` | 3 | release delay |
| `seed` | 20261022 | determinism |

## 7. Hazard lifecycle

```
observe(active)  -> evidence[source] = active; blockHazards[block].active = any(evidence)
                    block RED; previous block >= YELLOW; routes through block rejected
observe(clear)   -> evidence[source] = inactive; if all inactive:
                      hazard episode ends -> zone status RECOVERY_REQUIRED (restrictive)
RESET (existing) -> accepted only when no evidence active and sensors healthy -> NORMAL
```

Failure handling:
- MQTT down (Godot side): observation queued as today (one pending per publisher); onboard braking unaffected.
- MQTT down (backend/ESP side): ESP shows `COMM_LOSS` restrictive; backend `COMM_LOST`; no false clears.
- Stale or duplicate observations: rejected via `eventId`/timestamp; no state change.
- Camera detector disabled/unavailable: trackside path remains; local limits unchanged.
- Terrain/trees/bridges occluding an animal: no detection expected; a miss is not a fault.

## 8. Acceptance tests (must be automated)

1. Trackside-only detection stops the approaching train (Godot: hut → MQTT → backend hazard → block RED → train holds at approach boundary).
2. Camera-only detection stops the train with MQTT disconnected (Godot headless: detector → `set_local_wildlife_limit(0)` with bridge offline).
3. Both paths detect the same animal; evidence merges into one block hazard, one RED episode, no duplicate unsafe transitions (backend evidence test).
4. Terrain, trees, and a bridge each occlude the camera in detectors tests; the same animal is detected when the occluder is out of the sight line.
5. The opposite train continues when its route is unaffected (backend: hazard on `UP-B2` does not restrict `DOWN-B*` or `UP-B4`; fleet test).
6. A hazard near a crossover protects all conflicting routes (backend: route through `UP-B2`/`DOWN-B2` rejected while evidence active).
7. A clear observation does not bypass recovery: clear both sources → `RECOVERY_REQUIRED`; `RESET` rejected while any evidence active; accepted only when fully clear.
8. Both train cameras remain forward-aligned on straight sections and curves (Godot: camera forward ≈ carriage forward at multiple track distances, including curve apexes; `T1` and `T3` both).
9. Same random seed → same scenario sequence and outcomes (director determinism test).
10. Existing ESP32 native, Wokwi, dashboard, and Stage C/C1/C2 regression suites stay green (full-suite evidence recorded).

New test files:
- Backend: `wildlife_ingest.test.js`, `block_hazard.test.js`; plus updates to `signalling.test.js`, `state.test.js`, `routes.test.js`, `bus.test.js`.
- Godot: `test_sensor_huts.gd`, `test_wildlife_director.gd`, `test_onboard_camera.gd`, `test_onboard_braking.gd`; plus updates to `test_wildlife_safety.gd`, `test_wildlife_publisher.gd`, `test_esp32_integration.gd`.
- ESP32: new `test_logic` cases for backend-source wildlife commands.

## 9. Implementation sequence and exit gates

| Stage | Deliverable | Exit gate |
|---|---|---|
| 2F.1 | Wildlife scenario + trackside sensor network | Ten huts detect wildlife within 75 m coverage; director spawns random events with deterministic seed |
| 2F.2 | Per-train forward cameras + `AnimalDetector` interface | Correct forward alignment on straights and curves; range/cone/occlusion/confidence headless tests |
| 2F.3 | Backend block hazard + evidence + local braking | Either path initiates protection; block-scoped isolation; opposite train unaffected |
| 2F.4 | MQTT/ESP32 alert integration + recovery | Red light, buzzer, barrier active during episode; clear → `RECOVERY_REQUIRED` → `RESET` |
| 2F.5 | Full regression and evidence | Godot/backend/ESP32/web suites recorded in `docs/porting/acceptance.md`; captures reviewed |

Stage 2G (meet crossover chance) starts only after 2F's exit gate is met.

## 10. Out of scope

- Real ML model training/inference (interface only; ONNX/TFLite drop-in documented in 2F.2).
- Block/route-level signalling for arbitrary opposing runs (2G and beyond).
- Dashboard UI additions beyond exposing hazard fields in `/api/state`.
- Additional physical ESP32 devices or per-hut ESP hardware (single-device zone indicator remains).
