# Stage C2 Slices 2C–2E — Fleet Render, Interchange/Meet, and Integrated Delivery Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Stage C2 Phase 2 of the Railway Digital Twin:
1. **Slice 2C (Fleet Render):** Render two authoritative trains (`T1` on UP, `T3` on DOWN) with smooth distance interpolation from backend `railway/state`, 10 per-block signal masts with 3-aspect indicators, and HUD/Camera train selection.
2. **Slice 2D (Interchange & Meet):** Station crossover visual trajectory without snapping, animated switch blades, and a scripted meet/pass scenario with station framing camera.
3. **Slice 2E (Integration & Dashboard):** Level crossing wildlife protection covering both lines, React Dashboard updated with multi-train fleet display, block occupancy & signal lamps, and per-train speed control.

**Tech Stack:** Godot 4.7 GDScript, procedural meshes, React 18, TypeScript, Tailwind/CSS, Vite, Node.js ESM backend, MQTT.

**Spec Reference:** [`docs/superpowers/specs/2026-10-21-stage-c2-double-track-multitrain-design.md`](../specs/2026-10-21-stage-c2-double-track-multitrain-design.md) (§5.2, §5.3, §5.4, §6, §7).

---

## Global Constraints

- Educational simulation only; illustrative signalling and interlocking.
- Backend owns authoritative simulation, positions, blocks, and signal aspects; Godot interpolates and visualises.
- Local wildlife fail-safe strictly tightens speed: `min(backend_target, local_wildlife_limit)`.
- UP outer loop: radius `120.0 m`, length `753.9822 m`, 5 blocks (`UP-B0`..`UP-B4`).
- DOWN inner loop: radius `116.0 m`, length `728.8495 m`, 5 blocks (`DOWN-B0`..`DOWN-B4`).
- Keep all 22 existing Godot test suites green.
- All Godot tests run headless via `/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64` (or `bash godot/tests/run_tests.sh`).

---

## File Structure

- Create: `godot/src/block_signal_mast.gd` — 3-aspect signal mast with mast, head, red/yellow/green lenses, label
- Create: `godot/src/signal_director.gd` — places 10 masts at block boundaries on UP and DOWN tracks, listens to MQTT
- Create: `godot/src/fleet_controller.gd` — reads backend `trains[]`, maps to UP/DOWN tracks, interpolates poses
- Modify: `godot/src/ltstrain.gd` — support remote mode / pose updates without breaking local physics mode
- Modify: `godot/src/twin_hud.gd` — display fleet count, selected train, line, block, speed, aspect
- Modify: `godot/src/camera_director.gd` — support switching target train (`set_target_train`)
- Modify: `godot/src/scenario_director.gd` — meet/pass scenario execution
- Modify: `godot/scenes/lts_full.tscn` — wire `SignalDirector` and `FleetController`
- Modify: `godot/tests/test_parse.gd` — register new scripts
- Create: `godot/tests/test_signal_masts.gd` — verify mast placement and aspect switching
- Create: `godot/tests/test_fleet_controller.gd` — verify multi-train position mapping and interpolation
- Create: `godot/tests/test_fleet_hud.gd` — verify HUD train switching and camera targeting
- Modify: `web/src/App.tsx` — render multi-train fleet, block occupancy, per-train speed slider
- Modify: `web/src/style.css` — styling for fleet table, block indicators

---

### Task 1: BlockSignalMast and SignalDirector (Slice 2C)

**Files:**
- Create: `godot/src/block_signal_mast.gd`
- Create: `godot/src/signal_director.gd`
- Modify: `godot/scenes/lts_full.tscn`
- Modify: `godot/tests/test_parse.gd`
- Test: `godot/tests/test_signal_masts.gd`

**Interfaces:**
- `BlockSignalMast`: `set_aspect(aspect: String)` (GREEN, YELLOW, RED), `get_aspect() -> String`, `block_id: String`.
- `SignalDirector`: `get_mast(block_id: String) -> BlockSignalMast`, `get_aspect(block_id: String) -> String`, `update_aspect(block_id: String, aspect: String)`.
- 10 masts created: `UP-B0`..`UP-B4` and `DOWN-B0`..`DOWN-B4`.

- [x] **Step 1: Write failing test `godot/tests/test_signal_masts.gd`**
- [x] **Step 2: Run test to verify RED**
- [x] **Step 3: Implement `BlockSignalMast` and `SignalDirector`**
- [x] **Step 4: Run test to verify GREEN**
- [x] **Step 5: Verify tests and save changes**

---

### Task 2: FleetController and Remote Train Pose Interpolation (Slice 2C)

**Files:**
- Create: `godot/src/fleet_controller.gd`
- Modify: `godot/src/ltstrain.gd`
- Modify: `godot/scenes/lts_full.tscn`
- Modify: `godot/tests/test_parse.gd`
- Test: `godot/tests/test_fleet_controller.gd`

**Interfaces:**
- `FleetController`:
  - `apply_state(state: Dictionary)`
  - `get_train(train_id: String) -> LTSTrain`
  - `train_ids() -> Array[String]`
  - `calculate_track_distance(line: String, block_id: String, offset_m: float) -> float`
- `LTSTrain`:
  - `set_remote_mode(enabled: bool)`
  - `set_track_distance_m(distance_m: float)`
  - `set_track_line(line: String, track: LTSTrack)`

- [x] **Step 1: Write failing test `godot/tests/test_fleet_controller.gd`**
- [x] **Step 2: Run test to verify RED**
- [x] **Step 3: Implement `FleetController` and remote mode in `LTSTrain`**
- [x] **Step 4: Run test to verify GREEN**
- [x] **Step 5: Verify tests and save changes**

---

### Task 3: Multi-Train HUD and CameraDirector Switching (Slice 2C)

**Files:**
- Modify: `godot/src/twin_hud.gd`
- Modify: `godot/src/camera_director.gd`
- Test: `godot/tests/test_fleet_hud.gd`

**Interfaces:**
- `CameraDirector.set_target_train(train: Node3D)`
- `TwinHUD`:
  - `select_train(train_id: String)`
  - `cycle_selected_train()`
  - Displays selected train, line, block, speed, target, block aspect, fleet count
  - Preserves compatibility with single-train fallback

- [x] **Step 1: Write failing test `godot/tests/test_fleet_hud.gd`**
- [x] **Step 2: Run test to verify RED**
- [x] **Step 3: Implement train selection in HUD and CameraDirector**
- [x] **Step 4: Run test to verify GREEN**
- [x] **Step 5: Verify tests and save changes**

---

### Task 4: Station Crossover Visual Transition (Slice 2D)

**Files:**
- Modify: `godot/src/fleet_controller.gd`
- Modify: `godot/src/scenery_director.gd`
- Test: `godot/tests/test_crossover_visual.gd`

**Interfaces:**
- When a train's line transitions between UP and DOWN via `X-UP-DOWN` or `X-DOWN-UP`:
  - Interpolate across the crossover diagonal trajectory over transition duration
  - Animate switch blade indicators during traversal
  - Never teleport or snap

- [x] **Step 1: Write failing test `godot/tests/test_crossover_visual.gd`**
- [x] **Step 2: Run test to verify RED**
- [x] **Step 3: Implement crossover interpolation and switch blade animation**
- [x] **Step 4: Run test to verify GREEN**
- [x] **Step 5: Verify tests and save changes**

---

### Task 5: Scripted Meet/Pass Scenario and Station Camera (Slice 2D)

**Files:**
- Modify: `godot/src/scenario_director.gd`
- Modify: `godot/src/camera_director.gd`
- Test: `godot/tests/test_meet_scenario.gd`

**Interfaces:**
- `ScenarioDirector.run_meet_scenario()`:
  - Both trains approach platform blocks `UP-B2` / `DOWN-B2`
  - Dwell at station
  - Request crossover route
  - Pass and resume normal running
- `CameraDirector`: add `"station"` camera mode framing the island platform and both tracks

- [x] **Step 1: Write failing test `godot/tests/test_meet_scenario.gd`**
- [x] **Step 2: Run test to verify RED**
- [x] **Step 3: Implement meet/pass scenario and station camera**
- [x] **Step 4: Run test to verify GREEN**
- [x] **Step 5: Verify tests and save changes**

---

### Task 6: Dual-Track Level Crossing Wildlife Safety (Slice 2E)

**Files:**
- Modify: `godot/src/wildlife_safety.gd`
- Test: `godot/tests/test_wildlife_dual_track.gd`

**Interfaces:**
- When wildlife is detected at level crossing:
  - Both UP and DOWN approaching trains are held
  - Verify speed clamping across both trains

- [x] **Step 1: Write failing test `godot/tests/test_wildlife_dual_track.gd`**
- [x] **Step 2: Run test to verify RED**
- [x] **Step 3: Implement dual-track safety evaluation**
- [x] **Step 4: Run test to verify GREEN**
- [x] **Step 5: Verify tests and save changes**

---

### Task 7: React Dashboard Multi-Train & Block Signalling (Slice 2E)

**Files:**
- Modify: `web/src/App.tsx`
- Modify: `web/src/style.css`
- Test: `cd web && npm run build`

**Interfaces:**
- Display multi-train fleet (`trains[]`): ID, Line, Block, Speed, Target Speed, Status
- Block occupancy & signal aspect indicators for UP and DOWN lines
- Per-train target speed slider calling `POST /api/speed` with `{ trainId, speedKmh }`
- Station and crossover route status
- Maintain single-train backward compatibility

- [x] **Step 1: Update `web/src/App.tsx` and `web/src/style.css`**
- [x] **Step 2: Run `cd web && npm run build` to verify clean build**
- [x] **Step 3: Verify build and save changes**

---

### Task 8: Verification and Evidence (Slice 2E)

- [x] **Step 1: Run all Godot test suites (`bash godot/tests/run_tests.sh`)**
- [x] **Step 2: Verify all 74 unit backend tests pass**
- [x] **Step 3: Update documentation and acceptance record**
- [x] **Step 4: Verify complete delivery**
