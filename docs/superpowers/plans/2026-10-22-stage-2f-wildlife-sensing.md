# Stage 2F — Distributed Wildlife Sensing and Onboard Camera Detection Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Stage 2F distributed wildlife sensing: 10 trackside sensor huts (`UP-S0..S4`, `DOWN-S0..S4`), per-train forward ML camera detector with immediate local fail-safe stop (`set_local_wildlife_limit(0)`), backend block-scoped evidence fusion on `railway/wildlife`, ESP32 edge alert forwarding, and randomized proximity animal appearances with real-time animation.

**Architecture:**
- **Path A (Trackside):** 10 sensor huts at block boundaries with 75m `Area3D` coverage publish `railway/wildlife` (`source: "trackside"`). Backend merges into `blockHazards[block].evidence.trackside`, sets block `RED`, approach `YELLOW`, rejects conflicting routes, and edge-forwards alert to ESP32 (`railway/commands/esp32`).
- **Path B (Onboard ML Camera):** Lead cab camera runs `SimulatedAnimalDetector` (±25° cone, 180m, raycast occlusion against terrain, trees, bridges). Detection immediately triggers local braking `set_local_wildlife_limit(0)` without network round-trip, updates HUD vision overlay with confidence, and publishes `railway/wildlife` (`source: "onboard-camera"`).
- **Hazard Lifecycle:** Block hazard active if either trackside or onboard evidence is active. Clears when all evidence clear, enters `RECOVERY_REQUIRED`, and clears upon authorized `RESET`.

**Tech Stack:** Godot 4.7 GDScript, Node.js backend (Express + MQTT), C++ PlatformIO (ESP32 native), React + TypeScript web dashboard.

**Spec Reference:** [`docs/superpowers/specs/2026-10-22-stage-2f-distributed-wildlife-sensing-design.md`](file:///home/kathir/projects/railway-digital-twin/docs/superpowers/specs/2026-10-22-stage-2f-distributed-wildlife-sensing-design.md)

---

## File Structure & Responsibilities

| File | Responsibility |
|---|---|
| `mosquitto/acl_file` | Add `topic write railway/wildlife` to godot, `topic read railway/wildlife` to backend/dashboard |
| `backend/src/validate.js` | Validate `railway/wildlife` observation schema and parameters |
| `backend/src/state.js` | Block hazards state, evidence merging (`trackside`, `onboard`), recovery transition |
| `backend/src/signalling.js` | Map block hazard to signal aspects (`RED` on hazard block, `YELLOW` on approach) |
| `backend/src/routes.js` | Reject routes traversing hazard blocks |
| `backend/src/ingest.js` | Handle `railway/wildlife`, resolve `(line, distanceM)` to block ID, forward ESP32 alert |
| `backend/test/wildlife_observation.test.js` | Unit tests for observation validation and block hazard fusion |
| `esp32/src/command_logic.h` | Accept `source: "backend"` for `WILDLIFE_DETECTED` and `WILDLIFE_CLEARED` |
| `esp32/test/test_logic/test_logic.cpp` | Verify backend command source acceptance and actuator actions |
| `godot/src/onboard_braking.gd` | Pure stopping distance formula `d_stop(v)` and safe speed calculations |
| `godot/src/animal_detector.gd` | Abstract detector interface `detect(snapshot)` |
| `godot/src/simulated_animal_detector.gd` | Cone math, occlusion checks, confidence scoring, local stop trigger |
| `godot/src/wildlife_sensor_network.gd` | Trackside sensor hut placement and `Area3D` animal detection |
| `godot/src/wildlife_director.gd` | Proximity animal spawning (80-280m ahead), determinism, randomized cooldown |
| `godot/src/twin_hud.gd` | Render onboard ML camera detection badge and confidence |
| `web/src/App.tsx` | Render block hazard evidence badges on dashboard |

---

## Tasks

### Task 1: Mosquitto ACL & Backend Wildlife Observation Ingestion & State Fusion
- [x] Update `mosquitto/acl_file` to grant `godot` write and `backend`/`dashboard` read on `railway/wildlife`.
- [x] Add `validateWildlifeObservation(msg, config)` in `backend/src/validate.js`.
- [x] Update `backend/src/state.js` with `setBlockWildlifeEvidence(line, distanceM, observation)` managing `blockHazards`.
- [x] Update `backend/src/signalling.js` to consider active `blockHazards` in `deriveBlockAspects()`.
- [x] Update `backend/src/routes.js` to check block hazards along route.
- [x] Update `backend/src/ingest.js` for `railway/wildlife` and forward edge alert to `railway/commands/esp32`.
- [x] Create `backend/test/wildlife_observation.test.js` and verify with `node --test`.
- [x] Conventional Commit: `feat(backend): block-scoped wildlife evidence fusion and esp32 alert forwarding`.

### Task 2: ESP32 Backend Command Source Acceptance
- [x] Update `esp32/src/command_logic.h` to accept `source == "backend"` for `WILDLIFE_DETECTED` and `WILDLIFE_CLEARED`.
- [x] Add unit test in `esp32/test/test_logic/test_logic.cpp` verifying backend source acceptance.
- [x] Run `cd esp32 && /home/kathir/.local/bin/pio test -e native` to verify all 15 test cases pass.
- [x] Conventional Commit: `feat(esp32): support backend-forwarded wildlife alert events`.

### Task 3: Godot Stopping Distance Model & Onboard Simulated ML Camera Detector
- [x] Create `godot/src/onboard_braking.gd` implementing `stopping_distance(speed_kmh)` and `safe_speed_limit(distance_m)`.
- [x] Create `godot/src/animal_detector.gd` (abstract interface).
- [x] Create `godot/src/simulated_animal_detector.gd`:
  - 180m range, ±25° horizontal cone, ±10° vertical cone.
  - Occlusion checks against terrain (`TerrainGenerator`), trees (`SceneryDirector.tree_roots()`), and bridge decks.
  - Confidence calculation: `clamp01((1 - d / 180) * species_mult)`.
  - Debounce persistence: 2 positive evaluations (1 if critical `d_stop >= d`).
  - Fail-safe stop: immediate call to `TrainReconciler.set_local_wildlife_limit(0)`.
  - MQTT observation publisher to `railway/wildlife` (`source: "onboard-camera"`).
- [x] Attach `SimulatedAnimalDetector` to lead carriage camera in `godot/src/ltstrain.gd`.
- [x] Create `godot/tests/test_onboard_braking.gd` and `godot/tests/test_onboard_detector.gd`.
- [x] Run Godot headless test suites.
- [x] Conventional Commit: `feat(godot): onboard ML animal camera detector and instant braking`.

### Task 4: Godot Trackside Sensor Huts Network
- [x] Create `godot/src/wildlife_sensor_network.gd`:
  - Spawns 10 visible sensor huts (5 UP, 5 DOWN) at block boundaries `k * lineLength / 5`.
  - Visuals: equipment hut box, post, antenna, indicator lamp.
  - 75m radius `Area3D` cylinder checking bodies in group `wildlife`.
  - Publishes `railway/wildlife` (`source: "trackside"`).
- [x] Wire `SensorHuts` under `WorldWildlife` in `lts_full.tscn`.
- [x] Create `godot/tests/test_sensor_huts.gd`.
- [x] Run Godot headless test suites.
- [x] Conventional Commit: `feat(godot): distributed trackside sensor huts network`.

### Task 5: Godot Wildlife Director & Real-Time Proximity Spawning
- [x] Create `godot/src/wildlife_director.gd`:
  - Replaces legacy fixed crossing trigger with randomized proximity spawns (80–280m ahead of trains).
  - Deterministic PRNG using exported `seed` (default 20261022).
  - Cooldown 30–60s between events.
  - Animates animal crossing with perpendicular movement and tags `line` and `track_distance_m`.
- [x] Update `godot/src/twin_hud.gd` to render ML camera detection status (`CAM clear` / `CAM detect 0.82`) and sensor hut status.
- [x] Create `godot/tests/test_wildlife_director.gd`.
- [x] Run Godot headless test suites.
- [x] Conventional Commit: `feat(godot): randomized proximity animal spawning director and HUD vision`.

### Task 6: Web Dashboard Hazard Evidence Presentation
- [x] Update `web/src/App.tsx` to render block hazard evidence badges (`trackside` vs `onboard-camera`, confidence, sensor/train ID).
- [x] Update `web/src/style.css` for evidence badge styling.
- [x] Verify build: `cd web && npm run build`.
- [x] Conventional Commit: `feat(web): display block hazard evidence sources and confidence`.

### Task 7: Full Verification & Delivery Record
- [x] Run full backend test suite (`node --test ...`).
- [x] Run full Godot test suite (`run_tests.sh`).
- [x] Run ESP32 native tests (`pio test -e native`).
- [x] Update `docs/porting/acceptance.md` with Stage 2F verification gates.
- [x] Conventional Commit: `docs(2f): complete stage 2F verification and delivery record`.
