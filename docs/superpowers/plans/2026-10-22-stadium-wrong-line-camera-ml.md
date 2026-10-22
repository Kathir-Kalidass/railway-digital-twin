# Stadium Double Track, Interlocked Wrong-Line Route, and Camera-Confirmed Wildlife Stop — Implementation Plan

> **Status:** Complete — implemented, verified, and committed as `ef797dc`
> (2026-10-23). The two-frame confirmation policy in Task 19 is authoritative.

> **For the implementing engineer:** Use `superpowers:executing-plans` to work through this plan phase by phase. Use `superpowers:test-driven-development` for every task. Do not skip the failing-test step. Do not commit unless the user explicitly asks; the repository currently has an untracked approved spec and the user has not authorized commits.

**Goal:** Replace the circular test loop with a 250 m-straight stadium double track, run T1 clockwise and T3 anticlockwise, add an operator-triggered interlocked A→B→A wrong-line movement, and add the sensor-slow → camera/ML-confirm → stop chain.

**Architecture:** Godot renders both tracks from one analytic stadium sampler and drives train poses from physical chainage. The backend keeps operational chainage/block/offset state, converts to physical where needed, and owns signalling, route interlocking, staged hazards and camera confirmation. A standalone FastAPI/torchvision service classifies JPEG frames; the backend is authoritative about whether a hazard is `SUSPECTED` or `CONFIRMED`.

**Tech Stack:** Godot 4.7.2 GDScript; Node 22 + Express + node:test; React 18 + Vite + TypeScript; Python 3.10 + FastAPI + torchvision 0.25 + PyTorch 2.10; MQTT; ESP32 PlatformIO.

**Spec:** `docs/superpowers/specs/2026-10-22-stadium-wrong-line-route-design.md`

---

## Global Constraints

- Stadium: `S = 250 m`; UP `R = 120 m`, `L_up = 1253.9822 m`; DOWN `R = 116 m`, `L_down = 1228.8495 m`; spacing 4 m. **Both tracks are centred on the world origin.**
- Physical chainage increases clockwise on both tracks and starts at the south-west corner of the south straight. South straight is at `z = +R` and heads `+X`; north straight is at `z = -R` and heads `-X`.
- Operational chainage is UP: `physical = operational`; DOWN: `physical = L_down - operational`.
- 5 blocks per line: UP `250.7964 m`, DOWN `245.7699 m`.
- Zone map: `['zone1','zone2','zone2','zone2','zone1']`.
- Station blocks: `UP-B0`, `DOWN-B4`. A at physical `120 m`, B at physical `240 m`; station platform between them.
- Crossover table (all physical positions):
  - `X-A`: `UP-B0` from op `120.0000` → `DOWN-B4` to op `125.7699`, `atM = 120.0`.
  - `X-B`: `DOWN-B4` from op `5.7699` → `UP-B0` to op `240.0000`, `atM = 240.0`.
- T1 starts on UP, `travelSign = +1`; T3 starts on DOWN, `travelSign = -1`. `travelSign` survives line changes.
- Never use proportional track-length scaling on the stadium; use `map_to_parallel`.
- `trains[].physicalM`, `trains[].travelSign`, `trains[].routePhase`, `trains[].crossingProgress` are the Godot-facing fields.
- Meets become hold-only. `meets.crossoverChance` defaults to `0`, field retained.
- Camera/ML: 640×360 JPEG at 2 fps, quality 70, one in-flight upload; confirmation is backend-authoritative; evidence is gitignored.
- No ESP32-CAM, model training, or cloud streaming.
- Verification commands:
  - Godot single test: `/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_<name>.gd`
  - Godot suite: `bash godot/tests/run_tests.sh`
  - Backend single test: `npm --prefix backend test -- test/<name>.test.js`
  - Backend suite: `MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test`
  - ML: `cd ml && ML_STUB=1 python -m pytest tests -q`
  - ESP32: `pio test -e native --project-dir esp32`; `pio run -e esp32dev --project-dir esp32`
  - Web: `npm --prefix web run build`
  - Captures: `xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --path godot --resolution 1440x900 --rendering-method gl_compatibility --script res://tests/capture_<name>.gd`

---

## File Map

### Godot

- **Modify** `godot/src/ltstrack.gd` — stadium sampler, `map_to_parallel`, shifted-position override, lengths.
- **Modify** `godot/scenes/lts_full.tscn` — track exports, remove InnerTrack position offset.
- **Modify** `godot/src/ltstrain.gd` — `travel_sign`, signed movement, carriage order, orientation, wheel rotation.
- **Modify** `godot/src/fleet_controller.gd` — physical mapping, `physicalM`, `travelSign`, state-driven crossings.
- **Modify** `godot/src/scenery_director.gd` — station 150 m, A/B 120/240, `map_to_parallel`, stadium scenery bounds.
- **Modify** `godot/src/terrain_generator.gd` — size 800, river at `z = 0` (crosses east/west apexes under the railway bridges).
- **Modify** `godot/scenes/world_wildlife.tscn` — Bridge at `z = 0`.
- **Modify** `godot/src/camera_director.gd` — station camera at south straight.
- **Modify** `godot/src/simulated_animal_detector.gd` — owning train, line, chainage, `onboard-sensor`, caution.
- **Modify** `godot/src/trackside_sensor_hut.gd` — `line_length_m`, DOWN conversion.
- **Modify** `godot/src/wildlife_sensor_network.gd` — pass line length.
- **Modify** `godot/src/wildlife_director.gd` — `travelSign` spawning.
- **Modify** `godot/src/twin_hud.gd` — wrong-line and camera lines.
- **Modify** `godot/src/scenario_director.gd` — preserve route/physical fields in demo states.
- **Create** `godot/src/camera_confirmation.gd` — SubViewport JPEG capture + upload.
- **Create** `godot/tests/test_stadium_track.gd`
- **Create** `godot/tests/test_opposite_running.gd`
- **Create** `godot/tests/test_wrong_line_visual.gd`
- **Create** `godot/tests/test_wrong_line_hud.gd`
- **Create** `godot/tests/test_camera_confirmation.gd`
- **Modify** `godot/tests/test_fleet_controller.gd`, `test_track_registry.gd`, `test_station_crossovers.gd`, `test_station_island.gd`, `test_corridor_flatten.gd`, `test_catenary_double.gd`, `test_level_crossing_two_track.gd`, `test_river_bridges.gd`, `test_crossover_visual.gd`, `test_onboard_detector.gd`, `test_onboard_camera.gd`, `test_onboard_braking.gd`, `test_sensor_huts.gd`, `test_wildlife_director.gd`, `test_wildlife_dual_track.gd`.
- **Modify** `godot/tests/capture_station.gd`, `capture_crossover.gd`, `capture_double_track.gd`, `capture_meet.gd`, `capture_animals.gd`, `capture_scene.gd`.
- **Create** `godot/tests/capture_camera_confirm.gd`.
- **Modify** `docs/porting/acceptance.md` after each phase gate.

### Backend

- **Create** `backend/src/geometry.js` — operational/physical helpers.
- **Create** `backend/src/wrong_line.js` — route state machine.
- **Create** `backend/src/ml.js` — ML HTTP client.
- **Create** `backend/src/routes/wildlife.js` — camera ingest/health.
- **Create** `backend/test/geometry.test.js`
- **Create** `backend/test/wrong_line.test.js`
- **Create** `backend/test/wrong_line_api.test.js`
- **Create** `backend/test/camera.test.js`
- **Create** `backend/test/fixtures/stadium.js`
- **Modify** `backend/src/config.js` — topology, wrongLine, cameraConfirm, ml, meets.
- **Modify** `backend/src/railway.js` — preserve crossover fields and line lengths.
- **Modify** `backend/src/simulation.js` — skip set, `operationalSign`, staged speed caps.
- **Modify** `backend/src/signalling.js` — staged aspects, reservations.
- **Modify** `backend/src/state.js` — staged hazards, wrong-line wiring, snapshot.
- **Modify** `backend/src/validate.js` — offsets, onboard-sensor, wrong-line, camera headers.
- **Modify** `backend/src/meets.js` — hold-only.
- **Create** `backend/src/routes/wrong_line.js` — wrong-line request/cancel/read API.
- **Modify** `backend/src/app.js` — mount wrong-line and raw camera routers before the JSON body parser where needed.
- **Modify** `backend/src/loop.js` — publish wrong-line lifecycle events.
- **Modify** `backend/server.js` — inject ML client and evidence directory.
- **Modify** `backend/test/app_helpers.js` — inject ML/evidence.
- **Modify** `backend/test/config.test.js`, `railway.test.js`, `simulation.test.js`, `state.test.js`, `signalling.test.js`, `meets.test.js`, `routes.test.js`, `wildlife_observation.test.js`, `control_routes.test.js`, `validate.test.js`, `read_routes.test.js`.

### ML / Web / Docs

- **Create** `ml/app.py`, `ml/detector.py`, `ml/requirements.txt`, `ml/tests/test_detector.py`, `ml/tests/test_api.py`, `ml/README.md`.
- **Modify** `web/src/App.tsx`, `web/src/styles.css` (if needed), `web/package.json` only if a dependency is genuinely required.
- **Modify** `.gitignore` — `ml/.cache/`.
- **Modify** `docs/porting/acceptance.md`.

---

# Phase 1 — Stadium and Opposite Running

## Task 1: Stadium sampler and `map_to_parallel`

**Files:**
- Modify: `godot/src/ltstrack.gd`
- Create: `godot/tests/test_stadium_track.gd`

**Step 1: Write the failing test.**

Create `godot/tests/test_stadium_track.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var up := scene.get_node("Track") as LTSTrack
	var down := scene.get_node("InnerTrack") as LTSTrack
	a.ok(up != null and down != null, "both tracks exist")
	if up == null or down == null:
		quit(a.report("test_stadium_track"))
		return

	a.ok(absf(up.length - 1253.9822) < 0.01, "UP length is 2S + 2πR")
	a.ok(absf(down.length - 1228.8495) < 0.01, "DOWN length is 2S + 2πR")
	a.ok(absf(up.curve_radius_m - 120.0) < 0.001, "UP curve radius is 120 m")
	a.ok(absf(down.curve_radius_m - 116.0) < 0.001, "DOWN curve radius is 116 m")

	var up_points := {
		0.0: Vector3(-125.0, 0.0, 120.0),
		125.0: Vector3(0.0, 0.0, 120.0),
		250.0: Vector3(125.0, 0.0, 120.0),
		250.0 + PI * 120.0 * 0.5: Vector3(245.0, 0.0, 0.0),
		250.0 + PI * 120.0: Vector3(125.0, 0.0, -120.0),
		500.0 + PI * 120.0: Vector3(-125.0, 0.0, -120.0),
		500.0 + PI * 120.0 * 1.5: Vector3(-245.0, 0.0, 0.0),
	}
	for distance in up_points:
		var pose := up.get_global_transform_at_distance(distance)
		a.ok(pose.origin.distance_to(up_points[distance]) < 0.02,
			"UP pose at %.3f m is correct" % distance)

	a.ok(up.get_global_transform_at_distance(0.0).origin.distance_to(
		up.get_global_transform_at_distance(up.length).origin) < 0.02,
		"UP seam is continuous")
	a.ok(down.get_global_transform_at_distance(0.0).origin.distance_to(
		down.get_global_transform_at_distance(down.length).origin) < 0.02,
		"DOWN seam is continuous")

	for distance in [0.0, 125.0, 250.0, 344.2478, 438.4956, 626.9911, 751.2389, 876.9911, 1000.0]:
		var up_pose := up.get_global_transform_at_distance(distance)
		var down_pose := down.get_global_transform_at_distance(down.map_to_parallel(distance))
		a.ok(absf(up_pose.origin.distance_to(down_pose.origin) - 4.0) < 0.03,
			"parallel mapping keeps 4 m spacing at UP %.1f m" % distance)

	for distance in [0.0, 125.0, 250.0, 344.2478, 626.9911, 876.9911]:
		var round_trip := up.map_to_parallel(down.map_to_parallel(distance))
		a.ok(absf(round_trip - distance) < 0.02, "parallel mapping round-trips at %.1f m" % distance)

	var south_shifted := up.get_shifted_global_pos_at_distance(0.0, 12.0)
	a.ok(south_shifted.distance_to(Vector3(-125.0, 0.0, 132.0)) < 0.02,
		"positive shift is outside the UP rail on the south straight")

	scene.queue_free()
	await process_frame
	quit(a.report("test_stadium_track"))
```

**Step 2: Run it and confirm failure.**

Run: `/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_stadium_track.gd`

Expected: fails because `curve_radius_m`/`map_to_parallel` do not exist and the length is circular.

**Step 3: Implement the sampler.**

In `godot/src/ltstrack.gd`, extend the existing class:

```gdscript
@export var straight_length_m := 250.0
@export var curve_radius_m := 120.0
@export var parallel_curve_radius_m := 116.0

func _ready() -> void:
	length = 2.0 * straight_length_m + TAU * curve_radius_m
	radius = curve_radius_m
	_build_track_visuals()

func map_to_parallel(distance_m: float) -> float:
	var s := straight_length_m
	var r := curve_radius_m
	var pr := parallel_curve_radius_m if parallel_curve_radius_m > 0.0 else r
	var other_length := 2.0 * s + TAU * pr
	var d := fposmod(distance_m, length)
	if d <= s:
		return d
	if d <= s + PI * r:
		return s + (d - s) * pr / r
	if d <= 2.0 * s + PI * r:
		return d + PI * (pr - r)
	var west_offset := d - (2.0 * s + PI * r)
	return fposmod(2.0 * s + PI * pr + west_offset * pr / r, other_length)

func get_local_transform_at_distance(distance_m: float) -> Transform3D:
	var s := straight_length_m
	var r := curve_radius_m
	var d := fposmod(distance_m, length)
	var origin := Vector3.ZERO
	var forward := Vector3.RIGHT
	if d <= s:
		origin = Vector3(-s * 0.5 + d, 0.0, r)
		forward = Vector3.RIGHT
	elif d <= s + PI * r:
		var theta := PI * 0.5 - (d - s) / r
		origin = Vector3(s * 0.5 + r * cos(theta), 0.0, r * sin(theta))
		forward = Vector3(sin(theta), 0.0, -cos(theta))
	elif d <= 2.0 * s + PI * r:
		var along := d - (s + PI * r)
		origin = Vector3(s * 0.5 - along, 0.0, -r)
		forward = Vector3.LEFT
	else:
		var theta := -PI * 0.5 - (d - (2.0 * s + PI * r)) / r
		origin = Vector3(-s * 0.5 + r * cos(theta), 0.0, r * sin(theta))
		forward = Vector3(sin(theta), 0.0, -cos(theta))
	var basis := Basis(forward.normalized(), Vector3.UP, forward.cross(Vector3.UP).normalized())
	return Transform3D(basis, origin)

func get_shifted_local_pos_at_distance(distance_m: float, shift: float) -> Vector3:
	var pose := get_local_transform_at_distance(distance_m)
	return pose.origin + pose.basis.z * shift
```

Update `godot/scenes/lts_full.tscn`:

```ini
[node name="Track" type="Node3D" parent="."]
script = ExtResource("2")
straight_length_m = 250.0
curve_radius_m = 120.0
parallel_curve_radius_m = 116.0
max_speed_kmh = 80.0

[node name="InnerTrack" type="Node3D" parent="."]
script = ExtResource("2")
straight_length_m = 250.0
curve_radius_m = 116.0
parallel_curve_radius_m = 120.0
max_speed_kmh = 80.0
```

Remove the old `length`, `radius`, and `position` values from both nodes.

**Step 4: Run the test again.**

Expected: PASS. Then run `test_track_registry` and `test_train_loop`; they will fail on old expectations, which Task 2 fixes.

## Task 2: Scene, station, crossovers, scenery, terrain, cameras and captures

**Files:**
- Modify: `godot/src/scenery_director.gd`
- Modify: `godot/src/terrain_generator.gd`
- Modify: `godot/scenes/world_wildlife.tscn`
- Modify: `godot/src/camera_director.gd`
- Modify: `godot/tests/test_track_registry.gd`, `test_station_crossovers.gd`, `test_station_island.gd`, `test_corridor_flatten.gd`, `test_catenary_double.gd`, `test_level_crossing_two_track.gd`, `test_river_bridges.gd`, `test_camera_director.gd`
- Modify: `godot/tests/capture_station.gd`, `capture_crossover.gd`, `capture_double_track.gd`, `capture_meet.gd`, `capture_animals.gd`, `capture_scene.gd`

**Step 1: Update tests first.**

`godot/tests/test_track_registry.gd`:

```gdscript
a.ok(absf(down.curve_radius_m - 116.0) < 0.001, "inner curve radius is 116 m")
a.ok(absf(down.length - 1228.8495) < 0.01, "inner length is the stadium length")
a.ok(down.global_position.length() < 0.01, "inner track is centred on the origin")
a.ok(absf(registry.length_m("UP") - 1253.9822) < 0.01, "UP length exposed")

for distance in [0.0, 125.0, 250.0, 344.2478, 438.4956, 626.9911, 876.9911]:
	var up_pose: Transform3D = up.get_global_transform_at_distance(distance)
	var down_pose: Transform3D = down.get_global_transform_at_distance(down.map_to_parallel(distance))
	a.ok(absf(up_pose.origin.distance_to(down_pose.origin) - 4.0) < 0.05,
		"4 m spacing at UP %.1f m" % distance)
```

`godot/tests/test_station_crossovers.gd`:

```gdscript
for entry in [["CrossoverA", 120.0, "UP-B0", "DOWN-B4"], ["CrossoverB", 240.0, "UP-B0", "DOWN-B4"]]:
	var node_name: String = entry[0]
	var d_up: float = entry[1]
	var d_down: float = down.map_to_parallel(d_up)
	a.ok(d_up >= 0.0 and d_up < 250.7964, "%s is on the UP station block" % node_name)
	a.ok(d_down >= 0.0 and d_down < 245.7699, "%s is on the DOWN station block" % node_name)
	# ... keep midpoint, meta and blade assertions ...
```

`godot/tests/test_station_island.gd`:

```gdscript
var d_up: float = scenery.station_distance + module * scenery.station_module_spacing
var down_pose: Transform3D = down.get_global_transform_at_distance(down.map_to_parallel(d_up))
a.ok(d_up >= 0.0 and d_up < 250.7964, "module %d is inside UP-B0" % module)
var d_down := down.map_to_parallel(d_up)
a.ok(d_down >= 0.0 and d_down < 245.7699, "module %d is inside DOWN-B4" % module)
```

`godot/tests/test_corridor_flatten.gd`:

```gdscript
for distance in [0.0, 125.0, 250.0, 344.2478, 438.4956, 626.9911, 751.2389, 876.9911, 1000.0, 1125.0]:
	var up_point: Vector3 = up.get_global_transform_at_distance(distance).origin
	# ...
	var down_point: Vector3 = down.get_global_transform_at_distance(down.map_to_parallel(distance)).origin
	# ...
var river_y := terrain.height_at(0.0, 0.0)
a.ok(river_y < -2.0, "river channel is carved through the infield")

var river := scene.get_node("WorldWildlife/TerrainGenerator/RiverWater") as MeshInstance3D
a.ok(river != null and absf(river.global_position.z) < 0.01, "river water lies at z = 0")
```

`godot/tests/test_catenary_double.gd` and `godot/tests/test_level_crossing_two_track.gd`: replace `distance * down.length / up.length` with `down.map_to_parallel(distance)`.

`godot/tests/test_river_bridges.gd`:

```gdscript
var river_y := terrain.height_at(0.0, 0.0)
var bank_y := terrain.height_at(0.0, 40.0)
a.ok(river_y < -2.0, "river channel is carved below the water line")
a.ok(bank_y > river_y + 1.5, "river banks rise above the channel")
a.ok(absf(road_bridge.global_position.z) < 10.0, "road bridge spans the river")
a.ok(absf(pose_a.origin.z) < 10.0, "first railway bridge sits on the river crossing")
a.ok(absf(pose_b.origin.z) < 10.0, "second railway bridge sits on the river crossing")
```

`godot/tests/test_camera_director.gd`: no assertion changes, but after changing the station camera it must still pass; add:

```gdscript
director.set_mode("station")
await process_frame
a.ok(director.current_camera().global_position.z > 40.0, "station camera looks at the south straight")
```

**Step 2: Update scenery.**

In `godot/src/scenery_director.gd`:

```gdscript
@export var station_distance := 150.0
@export var crossover_a_up_distance := 120.0
@export var crossover_b_up_distance := 240.0
```

In `_pose_pair()`:

```gdscript
var down_pose := down.get_global_transform_at_distance(down.map_to_parallel(up_distance))
```

In `_build_crossover()`:

```gdscript
root.set_meta("down_distance", down.map_to_parallel(up_distance))
```

Update speed signs to `[[60.0, "40"], [260.0, "60"], [700.0, "80"]]` and tree bounds to `absf(pose.origin.x) > 380.0 or absf(pose.origin.z) > 380.0`.

**Step 3: Update terrain and the river.**

In `godot/src/terrain_generator.gd`:

```gdscript
@export var size := 800.0
@export var river_z := 0.0
```

In `godot/scenes/world_wildlife.tscn`:

```ini
[node name="Bridge" type="Node3D" parent="."]
position = Vector3(0, 0, 0)
script = ExtResource("2")
```

The river now cuts the infield at `z = 0`. The stadium crosses it at the east and west apexes, exactly where `RailwayBridgeA/B` sit (`distance_fraction` 0.25 and 0.75).

**Step 4: Update cameras and captures.**

In `godot/src/camera_director.gd`:

```gdscript
_station.position = Vector3(55.0, 26.0, 55.0)
_station.look_at(Vector3(-5.0, 2.0, 120.0), Vector3.UP)
```

Update capture scripts:

- `capture_station.gd`: top-down `(55, 90, 120)` looking at `(55, 0, 120)`; oblique `(110, 22, 165)` looking at `(20, 2, 120)`; resolution comment 1440×900.
- `capture_crossover.gd`: `center = Vector3(-5.0, 1.0, 120.0)`; camera `center + Vector3(42, 24, 20)`.
- `capture_double_track.gd`: camera `(0, 260, 0)` looking at `(0, 0, 0)`.
- `capture_meet.gd` and `capture_animals.gd`: derive the camera target from the train/crossing; remove hardcoded `z = -232` and `-120`.
- `capture_scene.gd`: overhead and wildlife shots derive positions from the train/crossing.

**Step 5: Run the focused tests.**

Run each:

```bash
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_track_registry.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_station_crossovers.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_station_island.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_corridor_flatten.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_catenary_double.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_level_crossing_two_track.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_river_bridges.gd
```

Expected: PASS. If a bridge pier or platform collides with the new geometry, adjust the asset offsets rather than weakening the test.

**Step 6: Capture the new layout.**

```bash
xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --path godot --resolution 1440x900 --rendering-method gl_compatibility --script res://tests/capture_double_track.gd
xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --path godot --resolution 1440x900 --rendering-method gl_compatibility --script res://tests/capture_station.gd
```

Expected files: `/tmp/opencode/double_track_overview.png`, `/tmp/opencode/platform_after_topdown.png`, `/tmp/opencode/platform_after_oblique.png`. Inspect them before continuing.

## Task 3: Backend stadium topology, geometry and validation

**Files:**
- Create: `backend/src/geometry.js`
- Create: `backend/test/geometry.test.js`
- Modify: `backend/src/config.js`
- Modify: `backend/src/railway.js`
- Modify: `backend/test/config.test.js`
- Modify: `backend/test/railway.test.js`
- Modify: `backend/test/validate.test.js`

**Step 1: Write the failing geometry tests.**

Create `backend/test/geometry.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { config } from '../src/config.js';
import { buildTopology, blockById } from '../src/railway.js';
import {
  blockOffsetToPhysical,
  operationalToPhysical,
  physicalToOperational,
  physicalToBlockOffset,
} from '../src/geometry.js';

test('line lengths and block offsets map in both directions', () => {
  const topo = buildTopology(config);
  assert.ok(Math.abs(topo.lines.find((l) => l.id === 'UP').lengthM - 1253.9822) < 0.001);
  assert.ok(Math.abs(topo.lines.find((l) => l.id === 'DOWN').lengthM - 1228.8495) < 0.001);

  assert.ok(Math.abs(operationalToPhysical(topo, 'UP', 120) - 120) < 0.001);
  assert.ok(Math.abs(operationalToPhysical(topo, 'DOWN', 988.8495) - 240) < 0.001);
  assert.ok(Math.abs(physicalToOperational(topo, 'DOWN', 240) - 988.8495) < 0.01);

  assert.ok(Math.abs(blockOffsetToPhysical(topo, 'UP', 'UP-B0', 120) - 120) < 0.001);
  assert.ok(Math.abs(blockOffsetToPhysical(topo, 'DOWN', 'DOWN-B4', 5.7699) - 240) < 0.01);

  const at = physicalToBlockOffset(topo, 'DOWN', 240);
  assert.equal(at.blockId, 'DOWN-B4');
  assert.ok(Math.abs(at.offsetM - 5.7699) < 0.01);
});

test('station blocks and zone map are the stadium layout', () => {
  const topo = buildTopology(config);
  assert.equal(topo.station.blocks.UP, 'UP-B0');
  assert.equal(topo.station.blocks.DOWN, 'DOWN-B4');
  assert.deepEqual(config.topology.zoneByIndex, ['zone1', 'zone2', 'zone2', 'zone2', 'zone1']);
  assert.equal(blockById(topo, 'UP-B0').zone, 'zone1');
  assert.equal(blockById(topo, 'DOWN-B4').zone, 'zone1');
});
```

**Step 2: Run and confirm failure.**

Run: `npm --prefix backend test -- test/geometry.test.js`

Expected: module not found / old topology values.

**Step 3: Update config.**

Replace the `topology` block in `backend/src/config.js`:

```js
topology: {
  lines: ['UP', 'DOWN'],
  blocksPerLine: 5,
  blockLengthM: 300,
  lineLengthM: { UP: 1253.9822, DOWN: 1228.8495 },
  zoneByIndex: ['zone1', 'zone2', 'zone2', 'zone2', 'zone1'],
  station: { id: 'station', name: 'Forest Halt', upIndex: 0, downIndex: 4, dwellSec: 20 },
  crossovers: [
    { id: 'X-A', from: 'UP-B0', fromOffsetM: 120.0, to: 'DOWN-B4', toOffsetM: 125.7699, atM: 120.0 },
    { id: 'X-B', from: 'DOWN-B4', fromOffsetM: 5.7699, to: 'UP-B0', toOffsetM: 240.0, atM: 240.0 },
  ],
},
```

Also set `meets.crossoverChance: 0` now.

**Step 4: Implement `geometry.js`.**

```js
const TAU = Math.PI * 2;
const mod = (v, n) => ((v % n) + n) % n;

export function lineLength(topology, line) {
  const found = topology.lines.find((l) => l.id === line);
  if (!found) throw new Error(`unknown line ${line}`);
  return found.lengthM;
}

export function operationalToPhysical(topology, line, operational) {
  const length = lineLength(topology, line);
  const value = mod(Number(operational), length);
  return line === 'DOWN' ? mod(length - value, length) : value;
}

export function physicalToOperational(topology, line, physical) {
  return operationalToPhysical(topology, line, physical);
}

export function blockOffsetToPhysical(topology, line, blockId, offsetM) {
  const block = topology.blocks.find((b) => b.id === blockId);
  if (!block || block.line !== line) throw new Error(`unknown block ${blockId}`);
  return operationalToPhysical(topology, line, block.index * block.lengthM + Number(offsetM));
}

export function physicalToBlockOffset(topology, line, physical) {
  const length = lineLength(topology, line);
  const value = mod(Number(physical), length);
  // Keep physical 0 on DOWN as operational L so it maps to the end of B4,
  // not the start of B0 at the same seam.
  const operational = line === 'DOWN' ? length - value : value;
  const lineObj = topology.lines.find((l) => l.id === line);
  const blockLength = length / lineObj.blocks.length;
  const index = Math.min(lineObj.blocks.length - 1, Math.floor(operational / blockLength));
  const blockId = lineObj.blocks[index];
  const block = topology.blocks.find((b) => b.id === blockId);
  return { blockId, offsetM: operational - block.index * block.lengthM };
}
```

Note: `blockOffsetToPhysical` uses the block's own operational index; `physicalToBlockOffset` is the inverse at block boundaries. Add a test for the seam:

```js
assert.ok(Math.abs(physicalToOperational(topo, 'DOWN', operationalToPhysical(topo, 'DOWN', 0)) - 0) < 0.001);
```

**Step 5: Preserve crossover fields and line lengths in `railway.js`.**

```js
export function buildTopology(config) {
  const t = config.topology;
  const blocks = [];
  const lines = [];
  for (const line of t.lines) {
    const ids = [];
    const lengthM = t.lineLengthM?.[line] ?? t.blockLengthM * t.blocksPerLine;
    const blockLengthM = Math.round((lengthM / t.blocksPerLine) * 1000) / 1000;
    for (let i = 0; i < t.blocksPerLine; i++) {
      const id = `${line}-B${i}`;
      blocks.push({ id, line, index: i, zone: t.zoneByIndex[i], lengthM: blockLengthM, occupiedBy: null, reservedBy: null });
      ids.push(id);
    }
    lines.push({ id: line, blocks: ids, lengthM });
  }
  const station = { ...t.station, blocks: { UP: `UP-B${t.station.upIndex}`, DOWN: `DOWN-B${t.station.downIndex}` } };
  const crossovers = (t.crossovers || []).map((r) => ({ ...r }));
  return { blocks, lines, station, crossovers };
}
```

**Step 6: Add offset validation.**

In `backend/src/config.js`, import:

```js
import { buildTopology, blockById } from './railway.js';
import { blockOffsetToPhysical } from './geometry.js';
```

Inside `validateConfig`:

```js
const topo = buildTopology(c);
for (const route of c.topology.crossovers || []) {
  const from = blockById(topo, route.from);
  const to = blockById(topo, route.to);
  if (!from || !to) continue;
  if (!(route.fromOffsetM >= 0 && route.fromOffsetM < from.lengthM)) errors.push(`crossover ${route.id} fromOffsetM out of range`);
  if (!(route.toOffsetM >= 0 && route.toOffsetM < to.lengthM)) errors.push(`crossover ${route.id} toOffsetM out of range`);
  const fromPhysical = blockOffsetToPhysical(topo, from.line, from.id, route.fromOffsetM);
  const toPhysical = blockOffsetToPhysical(topo, to.line, to.id, route.toOffsetM);
  if (!(Math.abs(fromPhysical - route.atM) < 0.001) || !(Math.abs(toPhysical - route.atM) < 0.001)) {
    errors.push(`crossover ${route.id} atM does not match its offsets`);
  }
}
```

**Step 7: Update config and railway tests.**

`config.test.js`:

```js
assert.equal(config.topology.lineLengthM.UP, 1253.9822);
assert.equal(config.topology.lineLengthM.DOWN, 1228.8495);
assert.equal(config.topology.station.upIndex, 0);
assert.equal(config.topology.station.downIndex, 4);
assert.deepEqual(config.topology.crossovers.map((c) => c.id), ['X-A', 'X-B']);
assert.equal(config.meets.crossoverChance, 0);
```

`railway.test.js`:

```js
assert.deepEqual(topo.station.blocks, { UP: 'UP-B0', DOWN: 'DOWN-B4' });
assert.equal(blockById(topo, 'UP-B0').lengthM, 250.796);
assert.equal(blockById(topo, 'DOWN-B4').lengthM, 245.77);
assert.equal(topo.crossovers[0].fromOffsetM, 120);
assert.equal(topo.crossovers[1].atM, 240);
```

**Step 8: Run the focused tests.**

```bash
npm --prefix backend test -- test/geometry.test.js test/config.test.js test/railway.test.js test/validate.test.js
```

Expected: PASS.

## Task 4: Direction-aware Godot movement

**Files:**
- Modify: `godot/src/ltstrain.gd`
- Modify: `godot/src/fleet_controller.gd`
- Modify: `godot/src/scenario_director.gd`
- Create: `godot/tests/test_opposite_running.gd`
- Modify: `godot/tests/test_fleet_controller.gd`

**Step 1: Write the failing test.**

Create `godot/tests/test_opposite_running.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var fleet := scene.get_node("FleetController") as FleetController
	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "UP", "block": "UP-B0", "offsetM": 40.0, "physicalM": 40.0, "travelSign": 1, "speedKmh": 36.0, "targetSpeedKmh": 36.0},
			{"id": "T3", "line": "DOWN", "block": "DOWN-B0", "offsetM": 0.0, "physicalM": 0.0, "travelSign": -1, "speedKmh": 36.0, "targetSpeedKmh": 36.0}
		]
	})

	var t1 := fleet.get_train("T1") as LTSTrain
	var t3 := fleet.get_train("T3") as LTSTrain
	a.ok(t1 != null and t3 != null, "both trains exist")
	if t1 == null or t3 == null:
		quit(a.report("test_opposite_running"))
		return

	a.ok(absf(t1.travel_sign - 1.0) < 0.001, "T1 travels clockwise")
	a.ok(absf(t3.travel_sign + 1.0) < 0.001, "T3 travels anticlockwise")
	a.ok(absf(t3.get_track_position_m()) < 0.1, "T3 starts at DOWN physical 0")

	var t3_locomotive := t3.get_node("Locomotive") as Node3D
	var t3_forward := t3_locomotive.global_basis.x.normalized()
	a.ok(t3_forward.dot(Vector3.RIGHT) < -0.9, "T3 faces west at the south straight")

	var t3_p1 := t3.get_track_position_m()
	t3.call("_physics_process", 0.2)
	var t3_p2 := t3.get_track_position_m()
	a.ok(t3_p2 < t3_p1 or t3_p2 > t3._track.length - 5.0, "T3 moves anticlockwise")

	var t1_start := t1.get_track_position_m()
	t1.call("_physics_process", 0.2)
	a.ok(t1.get_track_position_m() > t1_start, "T1 moves clockwise")

	var camera := t3.get_forward_camera()
	a.ok(camera != null, "T3 has a forward camera")
	if camera:
		var to_camera := (camera.global_position - t3_locomotive.global_position).normalized()
		a.ok(to_camera.dot(t3_forward) > 0.5, "T3 camera faces the direction of travel")

	scene.queue_free()
	await process_frame
	quit(a.report("test_opposite_running"))
```

Also update `test_fleet_controller.gd` expectations:

```gdscript
var expected_up_b1 := 250.7964 + 10.0
var expected_down_b2 := 1228.8495 - (245.7699 * 2.0)
```

**Step 2: Run and confirm failure.**

Expected: `travel_sign` missing; T3 moves clockwise; camera faces the wrong way.

**Step 3: Implement in `LTSTrain`.**

Add:

```gdscript
@export var travel_sign := 1.0
```

Change movement in `_physics_process`:

```gdscript
_track_position_m = fposmod(_track_position_m + _speed_mps * travel_sign * delta, _track.length)
```

In remote mode:

```gdscript
_track_position_m = fposmod(_track_position_m + _speed_mps * travel_sign * delta, track_len)
var err := fposmod(_target_distance_m - _track_position_m + track_len * 0.5, track_len) - track_len * 0.5
_track_position_m = fposmod(_track_position_m + err * minf(1.0, 3.0 * delta), track_len)
```

Change wheel rotation:

```gdscript
var rotation_delta := (_speed_mps * delta) / 0.48 * travel_sign
```

Change carriage placement and pose:

```gdscript
func _update_train_pose() -> void:
	if not is_instance_valid(_track):
		return
	for index in _carriages.size():
		var carriage_distance := fposmod(_track_position_m - index * 18.0 * travel_sign, _track.length)
		var pose := _track.get_global_transform_at_distance(carriage_distance)
		if travel_sign < 0.0:
			pose.basis = pose.basis.rotated(Vector3.UP, PI)
		if is_instance_valid(_blend_target_track) and _blend_target_track != _track and _blend_progress < 1.0:
			# keep the target mapping physical; do not scale by length
			var target_distance := fposmod(carriage_distance, _blend_target_track.length)
			var target_pose := _blend_target_track.get_global_transform_at_distance(target_distance)
			if travel_sign < 0.0:
				target_pose.basis = target_pose.basis.rotated(Vector3.UP, PI)
			pose = pose.interpolate_with(target_pose, _blend_progress)
		_carriages[index].global_transform = pose
```

**Step 4: Fix `FleetController.calculate_track_distance`.**

```gdscript
func calculate_track_distance(line: String, block_id: String, offset_m: float, physical_m := NAN) -> float:
	if not is_nan(physical_m):
		return fposmod(physical_m, _registry.length_m(line) if _registry else (1253.9822 if line == "UP" else 1228.8495))
	var line_len := 753.9822
	if _registry:
		line_len = _registry.length_m(line)
	elif line == "DOWN":
		line_len = 1228.8495
	else:
		line_len = 1253.9822
	var block_len := line_len / 5.0
	var block_index := 0
	if block_id.contains("-B"):
		var parts := block_id.split("-B")
		if parts.size() > 1:
			block_index = int(parts[1])
	var operational := block_index * block_len + offset_m
	if line == "DOWN":
		return fposmod(line_len - operational, line_len)
	return fposmod(operational, line_len)
```

In `apply_state`:

```gdscript
var travel_sign := float(item.get("travelSign", -1.0 if line == "DOWN" else 1.0))
var physical_m: Variant = item.get("physicalM")
var dist_m := calculate_track_distance(line, block, offset_m, float(physical_m) if physical_m != null else NAN)
# after train is valid:
train.travel_sign = travel_sign
```

In `_finish_crossover`:

```gdscript
var target_distance := source_distance
if is_instance_valid(source_track) and source_track.length > 0.0:
	target_distance = target_track.map_to_parallel(source_distance)
train.set_track(target_track)
train.set_track_position_m(target_distance)
```

**Step 5: Update `scenario_director.gd`.**

Every `fleet.apply_state({...})` train entry should include `physicalM` and `travelSign` derived from the block/offset for that playback, or omit them and let the fallback calculate. Add `travelSign` to the manual states so the demo does not flip T3:

```gdscript
{"id": "T1", "line": "UP", "block": "UP-B2", "offsetM": 20.0, "travelSign": 1, ...}
{"id": "T3", "line": "DOWN", "block": "DOWN-B3", "offsetM": 10.0, "travelSign": -1, ...}
```

**Step 6: Run tests.**

```bash
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_opposite_running.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_fleet_controller.gd
```

Expected: PASS.

## Task 5: Wildlife chainage and T3 detector fixes

**Files:**
- Modify: `godot/src/trackside_sensor_hut.gd`
- Modify: `godot/src/wildlife_sensor_network.gd`
- Modify: `godot/src/simulated_animal_detector.gd`
- Modify: `godot/src/wildlife_director.gd`
- Modify: `godot/src/ltstrain.gd` (detector wiring)
- Modify: `godot/tests/test_sensor_huts.gd`, `test_onboard_detector.gd`, `test_onboard_camera.gd`, `test_onboard_braking.gd`, `test_wildlife_director.gd`, `test_wildlife_dual_track.gd`
- Modify: `backend/src/validate.js`
- Modify: `backend/test/wildlife_observation.test.js`

**Step 1: Update tests first.**

`test_sensor_huts.gd` add a DOWN check:

```gdscript
var down_hut := network.call("get_hut", "DOWN-S0") as Node3D
a.ok(down_hut != null, "DOWN-S0 exists")
if down_hut:
	var down := scene.get_node("InnerTrack") as LTSTrack
	down_hut.set_meta("test_line_length", down.length)
	var obs: Dictionary = down_hut.call("get_last_observation")
	# after a forced scan with an animal parked at the hut, distanceM must be operational
	a.ok(float(obs.get("distanceM", 0.0)) <= down.length, "DOWN distance is operational")
```

Add a focused unit test for the conversion:

```gdscript
a.ok(absf(down_hut.call("physical_to_operational", 240.0) - (down.length - 240.0)) < 0.01,
	"DOWN physical 240 maps to operational L-240")
```

`test_onboard_detector.gd`:

```gdscript
a.eq(str(detector.get("line")), "DOWN" if detector.get("train_id") == "T3" else "UP", "detector line follows its train")
a.eq(str(detector.get("source")), "onboard-sensor", "geometric detector is a sensor, not a camera")
a.eq(reconciler.get_local_wildlife_limit(), 30.0, "sensor detection commands caution, not stop")
```

`test_wildlife_director.gd` add:

```gdscript
var down_event: Dictionary = director.call("trigger_proximity_event", "T3", "DOWN", 500.0, -1.0)
a.ok(float(down_event.get("distanceM")) < 500.0, "T3 spawns behind its physical position")
```

Backend `wildlife_observation.test.js`:

```js
const sensorObs = { eventId: 's1', source: 'onboard-sensor', line: 'UP', distanceM: 310, wildlifeDetected: true, trainId: 'T1', timestamp: now / 1000 };
assert.equal(validateWildlifeObservation(sensorObs, cfg).ok, true);
```

**Step 2: Implement DOWN conversion in the hut.**

Add `@export var line_length_m := 0.0` and:

```gdscript
func physical_to_operational(physical_m: float) -> float:
	if line == "DOWN" and line_length_m > 0.0:
		return fposmod(line_length_m - physical_m, line_length_m)
	return fposmod(physical_m, line_length_m if line_length_m > 0.0 else physical_m + 1.0)

func _operational_distance(track_distance_m: float) -> float:
	return physical_to_operational(track_distance_m)
```

Use `_operational_distance(track_d)` for `distanceM` in both detected and clear observations. Keep `boundary_distance_m` physical and convert only when publishing.

In `wildlife_sensor_network.gd`:

```gdscript
hut.line_length_m = track.length
```

**Step 3: Fix the T3 detector.**

In `SimulatedAnimalDetector`:

```gdscript
@export var source := "onboard-sensor"

var _chainage_m := 0.0

func _owner_train() -> LTSTrain:
	var node := get_parent()
	while node != null:
		if node is LTSTrain:
			return node as LTSTrain
		node = node.get_parent()
	return null

func _to_operational(physical_m: float, train: LTSTrain) -> float:
	var line_len := train.get_track_length_m()
	if line_len <= 0.0:
		return physical_m
	if train.line_id == "DOWN":
		return fposmod(line_len - physical_m, line_len)
	return fposmod(physical_m, line_len)

func _physics_process(delta: float) -> void:
	_tick_count += 1
	if _tick_count % camera_interval_ticks != 0:
		if _active_detection:
			_tick_clear_timer(delta)
		return

	var train := _owner_train()
	if is_instance_valid(train):
		train_id = train.train_id
		line = train.line_id
		_chainage_m = _to_operational(train.get_track_position_m(), train)
	var cam_trans := _camera.global_transform if is_instance_valid(_camera) else Transform3D.IDENTITY
	var speed_kmh := train.get_speed_kmh() if is_instance_valid(train) else 0.0
	# ...
```

Add the track length accessor in Task 4's `LTSTrain` changes alongside `travel_sign`:

```gdscript
func get_track_length_m() -> float:
	return _track.length if is_instance_valid(_track) else 0.0
```

Add `LTSTrain` exports:

```gdscript
@export var train_id := "T1"
@export var line_id := "UP"
@export var block_id := "UP-B0"
```

Set them in `FleetController.apply_state`:

```gdscript
train.train_id = id
train.line_id = line
train.block_id = block
```

Detector publishing:

```gdscript
var payload := {
	"eventId": event_id,
	"source": "onboard-sensor",
	"line": line,
	"distanceM": _chainage_m,
	"wildlifeDetected": detected,
	"species": str(det_info.get("species", "deer")),
	"count": 1 if detected else 0,
	"onTrack": detected,
	"trainId": train_id,
	"timestamp": Time.get_unix_time_from_system(),
}
```

Caution instead of stop:

```gdscript
func _apply_stop() -> void:
	if is_instance_valid(reconciler):
		reconciler.set_local_wildlife_limit(30.0)

func _lift_stop() -> void:
	if is_instance_valid(reconciler):
		reconciler.set_local_wildlife_limit(-1.0)
```

In `LTSTrain._attach_forward_camera`, pass the train:

```gdscript
detector.train_id = train_id
detector.line = line_id
detector.camera_path = cam.get_path()
```

**Step 4: Fix `WildlifeDirector` direction.**

```gdscript
var line_id := str(tid) if str(tid) == "T3" else "UP"
if is_instance_valid(_fleet):
	line_id = _fleet.get_train_line(str(tid))
var sign_value := t.travel_sign if is_instance_valid(t) else (-1.0 if line_id == "DOWN" else 1.0)
trigger_proximity_event(str(tid), line_id, t.get_track_position_m(), sign_value)

func trigger_proximity_event(train_id: String, line_id: String, train_pos: float, direction := 1.0) -> Dictionary:
	var lead_m := _rng.randf_range(spawn_lead_min_m, spawn_lead_max_m)
	var crossing_d := fposmod(train_pos + lead_m * direction, 1253.9822)
	# ...
```

Use the actual track length from `_registry.length_m(line_id)` when available.

**Step 5: Accept `onboard-sensor` in backend validation.**

In `validate.js`:

```js
if (!['trackside', 'onboard-sensor'].includes(source)) errors.push('source must be trackside or onboard-sensor');
...
} else if (source === 'onboard-sensor') {
  trainId = String(body?.trainId || '');
  if (!trainId) errors.push('trainId required for onboard-sensor');
}
```

Keep `onboard-camera` accepted for one release as a deprecated alias mapping to the same slot, so old clients do not break:

```js
if (!['trackside', 'onboard-sensor', 'onboard-camera'].includes(source)) ...
if (source === 'onboard-sensor' || source === 'onboard-camera') ...
```

**Step 6: Run tests.**

```bash
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_sensor_huts.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_onboard_detector.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_wildlife_director.gd
npm --prefix backend test -- test/wildlife_observation.test.js
```

Expected: PASS.

## Task 6: Phase 1 gate

**Step 1: Run the full suites.**

```bash
bash godot/tests/run_tests.sh
MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test
pio test -e native --project-dir esp32
npm --prefix web run build
```

Expected: Godot 34+ PASS, backend 106+ PASS, ESP32 15/15, web build PASS. Fix every regression before Phase 2.

**Step 2: Visual acceptance.**

Run the Phase 1 captures from Task 2. Inspect:
- stadium outline, 250 m straights, no circular look;
- station platform and A/B on the south straight;
- T1 clockwise, T3 anticlockwise, correct carriage order and camera;
- river under the east/west railway bridges.

**Step 3: Update `docs/porting/acceptance.md`.**

Add a short Phase 1 section with the capture paths and the test counts. Do not commit.

---

# Phase 2 — Interlocked Wrong-Line Route + Operator UI

## Task 7: Backend wrong-line state machine

**Files:**
- Create: `backend/src/wrong_line.js`
- Create: `backend/test/wrong_line.test.js`
- Modify: `backend/src/config.js`

**Step 1: Add config.**

```js
wrongLine: {
  enabled: true,
  speedKmh: 30,
  approachMinM: 40,
  approachMaxM: 220,
  crossingLengthM: 20,
  holdBeforeEntryM: 80,
  stopMarginM: 25,
  timeoutSec: 120,
},
```

Validate: `speedKmh > 0`, `approachMinM >= 0`, `approachMaxM > approachMinM`, `crossingLengthM > 0`, `holdBeforeEntryM >= 0`, `stopMarginM >= 0`, `timeoutSec > 0`.

**Step 2: Write the failing unit tests.**

Create `backend/test/wrong_line.test.js`. Use the real config and topology, and set blocks/offsets directly:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { config } from '../src/config.js';
import { buildTopology, blockById } from '../src/railway.js';
import { makeWrongLine } from '../src/wrong_line.js';

function world({ hazard = false, meet = false } = {}) {
  const topology = buildTopology(config);
  const zones = Object.fromEntries(config.zones.map((id) => [id, {
    id, targetSpeedKmh: 48, wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL',
  }]));
  const trains = [
    { id: 'T1', line: 'UP', block: 'UP-B0', offsetM: 40, speedKmh: 48, targetSpeedKmh: 48, commandedSpeedKmh: null, lengthM: 60, travelSign: 1, zone: 'zone1' },
    { id: 'T3', line: 'DOWN', block: 'DOWN-B2', offsetM: 0, speedKmh: 45, targetSpeedKmh: 45, commandedSpeedKmh: null, lengthM: 60, travelSign: -1, zone: 'zone2' },
  ];
  const wl = makeWrongLine({
    topology, trains, zones, config,
    hasActiveHazard: (id) => hazard && (id === 'UP-B0' || id === 'DOWN-B4'),
    isMeetActive: () => meet,
  });
  return { topology, trains, zones, wl };
}

test('eligibility reports approach distance and section state', () => {
  const { wl } = world();
  let e = wl.snapshot().eligibility;
  assert.equal(e.T1.eligible, true);
  assert.ok(Math.abs(e.T1.distanceToEntryM - 80) < 0.1);
  assert.equal(e.T3.eligible, false);
  assert.equal(e.T3.reason, 'approach');

  const blocked = world({ meet: true }).wl.snapshot().eligibility;
  assert.equal(blocked.T1.reason, 'meet_active');

  const hazard = world({ hazard: true }).wl.snapshot().eligibility;
  assert.equal(hazard.T1.reason, 'hazard');
});

test('T1 completes APPROACH -> CROSS_ENTRY -> WRONG_LINE -> CROSS_EXIT -> CLEARANCE -> DONE', () => {
  const { trains, wl } = world();
  const t1 = trains[0];
  const t3 = trains[1];
  const granted = wl.request({ trainId: 'T1' });
  assert.equal(granted.ok, true);
  assert.equal(wl.snapshot().active.phase, 'APPROACH');
  assert.equal(t3.commandedSpeedKmh, 0);
  assert.equal(blockById(wl.topology, 'UP-B0').reservedBy.startsWith('WL-'), true);

  t1.block = 'UP-B0';
  t1.offsetM = 120;
  wl.tick(0.5);
  assert.equal(wl.snapshot().active.phase, 'CROSS_ENTRY');
  assert.equal(t1.line, 'DOWN');
  assert.equal(t1.operationalSign, -1);

  for (let i = 0; i < 80 && wl.snapshot().active; i++) wl.tick(0.5);
  const snap = wl.snapshot();
  assert.equal(snap.active, null);
  assert.equal(snap.lastEvent, 'WRONG_LINE_COMPLETED');
  assert.equal(t1.line, 'UP');
  assert.equal(t1.operationalSign, 1);
  assert.equal(t3.commandedSpeedKmh, null);
  assert.equal(blockById(wl.topology, 'UP-B0').reservedBy, null);
  assert.equal(blockById(wl.topology, 'DOWN-B4').reservedBy, null);
});

test('cancel is allowed only during APPROACH', () => {
  const { trains, wl } = world();
  assert.equal(wl.request({ trainId: 'T1' }).ok, true);
  assert.equal(wl.cancel({ trainId: 'T1' }).ok, true);
  assert.equal(wl.snapshot().active, null);
  assert.equal(trains[1].commandedSpeedKmh, null);
});

test('hazard aborts and releases after the section clears', () => {
  let hazard = false;
  const topology = buildTopology(config);
  const zones = Object.fromEntries(config.zones.map((id) => [id, { id, targetSpeedKmh: 48, wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' }]));
  const trains = [
    { id: 'T1', line: 'UP', block: 'UP-B0', offsetM: 120, speedKmh: 30, targetSpeedKmh: 30, commandedSpeedKmh: null, lengthM: 60, travelSign: 1, zone: 'zone1' },
    { id: 'T3', line: 'DOWN', block: 'DOWN-B2', offsetM: 0, speedKmh: 45, targetSpeedKmh: 45, commandedSpeedKmh: null, lengthM: 60, travelSign: -1, zone: 'zone2' },
  ];
  const wl = makeWrongLine({ topology, trains, zones, config, hasActiveHazard: () => hazard, isMeetActive: () => false });
  assert.equal(wl.request({ trainId: 'T1' }).ok, true);
  wl.tick(0.5);
  hazard = true;
  wl.tick(0.5);
  assert.equal(wl.snapshot().active.phase, 'ABORTED_BLOCKED');
  hazard = false;
  wl.tick(0.5);
  assert.equal(wl.snapshot().active, null);
  assert.equal(wl.snapshot().lastEvent, 'WRONG_LINE_ABORTED');
});
```

The test uses `wl.topology`; expose it in the returned object.

**Step 3: Implement `wrong_line.js`.**

```js
import { blockById } from './railway.js';
import { blockOffsetToPhysical, physicalToBlockOffset } from './geometry.js';

const sectionBlockIds = (topology) => [topology.station.blocks.UP, topology.station.blocks.DOWN];
const mod = (v, n) => ((v % n) + n) % n;

export function makeWrongLine({ topology, trains, zones, config, hasActiveHazard = () => false, isMeetActive = () => false }) {
  const cfg = config.wrongLine || {};
  const stationBlocks = sectionBlockIds(topology);
  const definitions = new Map((topology.crossovers || []).map((c) => [c.id, c]));
  const travelSign = (t) => Number.isFinite(t.travelSign) ? t.travelSign : (t.line === 'DOWN' ? -1 : 1);
  const lineLengthFor = (line) => topology.lines.find((l) => l.id === line).lengthM;
  const physicalOf = (t) => Number.isFinite(t.physicalM)
    ? mod(t.physicalM, lineLengthFor(t.line))
    : blockOffsetToPhysical(topology, t.line, t.block, t.offsetM);
  let active = null;
  let ticket = 0;
  let lastEvent = null;
  const history = [];

  function routeForLine(line) {
    return line === 'UP'
      ? { entry: definitions.get('X-A'), exit: definitions.get('X-B') }
      : { entry: definitions.get('X-B'), exit: definitions.get('X-A') };
  }

  function entryPhysicalFor(t) {
    const route = routeForLine(t.line);
    return route.entry?.atM ?? 0;
  }

  function opponentHoldPhysical(routeTrain, opponent, exitPhysical) {
    return exitPhysical - (cfg.holdBeforeEntryM || 0) * travelSign(opponent);
  }

  function restrictive(blockId) {
    const block = blockById(topology, blockId);
    const zone = block ? zones[block.zone] : null;
    return !zone || zone.wildlifeDetected || !zone.sensorHealthy || zone.status === 'RECOVERY_REQUIRED';
  }

  function sectionOccupant(trainId) {
    return stationBlocks.find((id) => {
      const block = blockById(topology, id);
      return block && block.occupiedBy && block.occupiedBy !== trainId;
    }) || null;
  }

  function evaluate(train) {
    const other = trains.find((t) => t.id !== train.id);
    const route = routeForLine(train.line);
    const entry = entryPhysicalFor(train);
    const exit = route.exit?.atM ?? entry;
    const distance = (entry - physicalOf(train)) * travelSign(train);
    const base = { eligible: false, reason: null, distanceToEntryM: Math.round(distance * 10) / 10 };
    if (!cfg.enabled) return { ...base, reason: 'disabled' };
    if (active) return { ...base, reason: 'route_busy' };
    if (isMeetActive()) return { ...base, reason: 'meet_active' };
    if (stationBlocks.some((id) => hasActiveHazard(id))) return { ...base, reason: 'hazard' };
    if (stationBlocks.some((id) => restrictive(id))) return { ...base, reason: 'restrictive_zone' };
    if (distance < (cfg.approachMinM || 0) || distance > (cfg.approachMaxM || 0)) return { ...base, reason: 'approach' };
    if (sectionOccupant(train.id)) return { ...base, reason: 'section_occupied' };
    if (!other) return { ...base, reason: 'opposing_missing' };
    const hold = opponentHoldPhysical(train, other, exit);
    const opponentDistance = (hold - physicalOf(other)) * travelSign(other);
    const stopM = Math.pow(Math.max(0, other.speedKmh) / 3.6, 2) / (2 * (config.simulation?.brakeMps2 || 2.0));
    if (opponentDistance < stopM + (cfg.stopMarginM || 0)) return { ...base, reason: 'opposing_too_close' };
    return { ...base, eligible: true, reason: null };
  }

  function eligibility() {
    return Object.fromEntries(trains.map((t) => [t.id, evaluate(t)]));
  }

  function setPhysical(train, line, physical) {
    const placed = physicalToBlockOffset(topology, line, physical);
    train.line = line;
    train.block = placed.blockId;
    train.offsetM = placed.offsetM;
    train.physicalM = mod(physical, lineLengthFor(line));
  }

  function reserve(on) {
    for (const id of stationBlocks) {
      const block = blockById(topology, id);
      if (block) block.reservedBy = on ? active.routeId : null;
    }
  }

  function finish(event) {
    if (!active) return null;
    const routeTrain = trains.find((t) => t.id === active.trainId);
    const opponent = trains.find((t) => t.id === active.heldTrainId);
    if (routeTrain) {
      routeTrain.commandedSpeedKmh = active.savedRouteSpeed;
      routeTrain.routePhase = null;
      routeTrain.crossingProgress = 0;
      routeTrain.crossoverId = null;
    }
    if (opponent) opponent.commandedSpeedKmh = active.savedOpponentSpeed;
    reserve(false);
    history.push({ ...active, finishedAtTick: ticket, outcome: event });
    if (history.length > 10) history.shift();
    lastEvent = event;
    active = null;
    return event;
  }

  function request({ trainId }) {
    if (active) return { ok: false, reason: 'route_busy' };
    const train = trains.find((t) => t.id === trainId);
    if (!train) return { ok: false, reason: `unknown train ${trainId}` };
    const e = evaluate(train);
    if (!e.eligible) return { ok: false, reason: e.reason };
    const other = trains.find((t) => t.id !== trainId);
    const route = routeForLine(train.line);
    ticket += 1;
    active = {
      routeId: `WL-${trainId}-${ticket}`,
      trainId,
      heldTrainId: other.id,
      originalLine: train.line,
      destinationLine: train.line === 'UP' ? 'DOWN' : 'UP',
      entryCrossover: route.entry.id,
      exitCrossover: route.exit.id,
      entryPhysicalM: route.entry.atM,
      exitPhysicalM: route.exit.atM,
      holdPhysicalM: opponentHoldPhysical(train, other, route.exit.atM),
      phase: 'APPROACH',
      progress: 0,
      crossingProgress: 0,
      elapsedSec: 0,
      savedRouteSpeed: train.commandedSpeedKmh ?? null,
      savedOpponentSpeed: other.commandedSpeedKmh ?? null,
      operationalSign: train.operationalSign || 1,
    };
    reserve(true);
    other.commandedSpeedKmh = 0;
    train.commandedSpeedKmh = cfg.speedKmh;
    lastEvent = 'WRONG_LINE_GRANTED';
    return { ok: true, route: snapshot().active };
  }

  function beginEntry(train, route) {
    active.phase = 'CROSS_ENTRY';
    active.crossingProgress = 0;
    setPhysical(train, active.destinationLine, active.entryPhysicalM);
    train.operationalSign = -1;
    train.routePhase = 'CROSS_ENTRY';
  }

  function updateProgress() {
    if (!active) return 0;
    const weights = { APPROACH: 0.2, CROSS_ENTRY: 0.1, WRONG_LINE: 0.4, CROSS_EXIT: 0.1, CLEARANCE: 0.2 };
    const base = { APPROACH: 0, CROSS_ENTRY: 0.2, WRONG_LINE: 0.3, CROSS_EXIT: 0.7, CLEARANCE: 0.8, ABORTED_BLOCKED: 1 };
    let p = base[active.phase] ?? 0;
    if (active.phase === 'CROSS_ENTRY' || active.phase === 'CROSS_EXIT') p += weights[active.phase] * active.crossingProgress;
    if (active.phase === 'WRONG_LINE') {
      const total = Math.abs(active.exitPhysicalM - active.entryPhysicalM) - (cfg.crossingLengthM || 0) * 2;
      const done = Math.abs(physicalOf(trains.find((t) => t.id === active.trainId)) - active.entryPhysicalM) - (cfg.crossingLengthM || 0);
      p += weights.WRONG_LINE * Math.max(0, Math.min(1, done / Math.max(1, total)));
    }
    if (active.phase === 'CLEARANCE') {
      const t = trains.find((x) => x.id === active.trainId);
      const done = Math.abs(physicalOf(t) - active.exitPhysicalM);
      p += weights.CLEARANCE * Math.min(1, done / Math.max(1, t.lengthM));
    }
    return Math.max(0, Math.min(1, p));
  }

  function tick(dtSec) {
    const events = [];
    if (!active) return events;
    const train = trains.find((t) => t.id === active.trainId);
    const opponent = trains.find((t) => t.id === active.heldTrainId);
    if (!train || !opponent) { events.push(finish('WRONG_LINE_ABORTED')); return events; }
    active.elapsedSec = (active.elapsedSec || 0) + dtSec;
    opponent.commandedSpeedKmh = 0;
    active.progress = updateProgress();

    if (active.phase === 'APPROACH') {
      const distance = (active.entryPhysicalM - physicalOf(train)) * travelSign(train);
      if (distance <= 0.5) beginEntry(train);
      if (active.elapsedSec > cfg.timeoutSec) {
        train.commandedSpeedKmh = 0;
        opponent.commandedSpeedKmh = 0;
        events.push(finish('WRONG_LINE_TIMEOUT'));
      }
      return events;
    }

    if (stationBlocks.some((id) => hasActiveHazard(id))) {
      train.commandedSpeedKmh = 0;
      active.phase = 'ABORTED_BLOCKED';
      train.routePhase = 'ABORTED_BLOCKED';
      if (lastEvent !== 'WRONG_LINE_ABORTED_BLOCKED') {
        lastEvent = 'WRONG_LINE_ABORTED_BLOCKED';
        events.push(lastEvent);
      }
      return events;
    }
    if (active.phase === 'ABORTED_BLOCKED') {
      events.push(finish('WRONG_LINE_ABORTED'));
      return events;
    }

    if (opponent && stationBlocks.includes(opponent.block)) {
      train.commandedSpeedKmh = 0;
      opponent.commandedSpeedKmh = 0;
      events.push(finish('WRONG_LINE_INTRUSION'));
      return events;
    }

    const speed = (cfg.speedKmh || 30) / 3.6;
    if (active.phase === 'CROSS_ENTRY') {
      active.crossingProgress = Math.min(1, active.crossingProgress + speed * dtSec / (cfg.crossingLengthM || 20));
      const physical = active.entryPhysicalM + travelSign(train) * (cfg.crossingLengthM || 20) * active.crossingProgress;
      setPhysical(train, active.destinationLine, physical);
      if (active.crossingProgress >= 1) {
        active.phase = 'WRONG_LINE';
        train.routePhase = 'WRONG_LINE';
      }
    } else if (active.phase === 'WRONG_LINE') {
      const exitStart = active.exitPhysicalM - travelSign(train) * (cfg.crossingLengthM || 20);
      const next = physicalOf(train) + travelSign(train) * speed * dtSec;
      if ((next - exitStart) * travelSign(train) >= 0) {
        setPhysical(train, active.destinationLine, exitStart);
        active.phase = 'CROSS_EXIT';
        active.crossingProgress = 0;
        train.routePhase = 'CROSS_EXIT';
      } else {
        setPhysical(train, active.destinationLine, next);
      }
    } else if (active.phase === 'CROSS_EXIT') {
      active.crossingProgress = Math.min(1, active.crossingProgress + speed * dtSec / (cfg.crossingLengthM || 20));
      const physical = active.exitPhysicalM - travelSign(train) * (cfg.crossingLengthM || 20) * (1 - active.crossingProgress);
      setPhysical(train, active.destinationLine, physical);
      if (active.crossingProgress >= 1) {
        setPhysical(train, active.originalLine, active.exitPhysicalM);
        train.operationalSign = 1;
        active.phase = 'CLEARANCE';
        train.routePhase = 'CLEARANCE';
      }
    } else if (active.phase === 'CLEARANCE') {
      const next = physicalOf(train) + travelSign(train) * speed * dtSec;
      setPhysical(train, active.originalLine, next);
      if ((physicalOf(train) - active.exitPhysicalM) * travelSign(train) >= train.lengthM) {
        events.push(finish('WRONG_LINE_COMPLETED'));
      }
    }
    active.progress = updateProgress();
    return events;
  }

  function afterStep() {
    if (!active || active.phase !== 'APPROACH') return;
    const train = trains.find((t) => t.id === active.trainId);
    if (!train) return;
    const distance = (active.entryPhysicalM - physicalOf(train)) * travelSign(train);
    if (distance <= 0.5) beginEntry(train);
  }

  function cancel({ trainId }) {
    if (!active) return { ok: false, reason: 'no active route' };
    if (active.trainId !== trainId) return { ok: false, reason: 'train does not own route' };
    if (active.phase !== 'APPROACH') return { ok: false, reason: 'cancel only allowed during approach' };
    finish('WRONG_LINE_CANCELLED');
    return { ok: true };
  }

  function skipIds() {
    if (!active || active.phase === 'APPROACH') return [];
    return [active.trainId];
  }

  function snapshot() {
    return {
      active: active ? {
        trainId: active.trainId, routeId: active.routeId, phase: active.phase,
        entryCrossover: active.entryCrossover, exitCrossover: active.exitCrossover,
        progress: Math.round(active.progress * 1000) / 1000,
        crossingProgress: Math.round(active.crossingProgress * 1000) / 1000,
        heldTrainId: active.heldTrainId, holdPhysicalM: active.holdPhysicalM,
        elapsedSec: Math.round((active.elapsedSec || 0) * 1000) / 1000,
      } : null,
      eligibility: eligibility(),
      lastEvent,
      history: history.map((h) => ({ ...h })),
    };
  }

  return { request, cancel, tick, afterStep, snapshot, skipIds, eligibility, topology };
}
```

**Step 4: Run the tests.**

```bash
npm --prefix backend test -- test/wrong_line.test.js
```

Expected: PASS. If the lifecycle is too slow for the loop, the test loop of 80 × 0.5 s is enough for 240 m of physical movement plus clearance.

## Task 8: State, API, audit and RBAC integration

**Files:**
- Modify: `backend/src/state.js`
- Modify: `backend/src/validate.js`
- Create: `backend/src/routes/wrong_line.js`
- Modify: `backend/src/app.js`
- Modify: `backend/src/loop.js`
- Modify: `backend/src/simulation.js`
- Modify: `backend/test/simulation.test.js`
- Modify: `backend/test/state.test.js`
- Modify: `backend/test/control_routes.test.js`
- Create: `backend/test/wrong_line_api.test.js`

**Step 1: Write failing API tests.**

`backend/test/wrong_line_api.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildDeps, withServer, login } from './app_helpers.js';
import { config } from '../src/config.js';

test('wrong-line API enforces auth, RBAC and eligibility', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const anon = await fetch(`${url}/api/routes/wrong-line`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ trainId: 'T1' }) });
    assert.equal(anon.status, 401);
    const viewer = (await login(url, 'viewer', config.seedUsers.find((u) => u.role === 'viewer').password)).body.token;
    assert.equal((await fetch(`${url}/api/routes/wrong-line`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${viewer}` }, body: JSON.stringify({ trainId: 'T1' }) })).status, 403);

    const operator = (await login(url, 'operator', config.seedUsers.find((u) => u.role === 'operator').password)).body.token;
    const read = await fetch(`${url}/api/routes/wrong-line`, { headers: { authorization: `Bearer ${operator}` } });
    assert.equal(read.status, 200);
    const body = await read.json();
    assert.ok(body.eligibility.T1);
    assert.equal(body.active, null);
  });
});
```

Update `simulation.test.js`:

```js
test('occupyBlocks respects reverse operational movement', () => {
  const topo = buildTopology(config);
  const t = train({ block: 'UP-B1', offsetM: 40, lengthM: 60, operationalSign: -1 });
  occupyBlocks(topo, [t]);
  assert.equal(topo.blocks.find((b) => b.id === 'UP-B1').occupiedBy, 'T1');
  assert.equal(topo.blocks.find((b) => b.id === 'UP-B0').occupiedBy, 'T1');
  assert.equal(topo.blocks.find((b) => b.id === 'UP-B2').occupiedBy, null);
});

test('stepTrains skips a route-controlled train', () => {
  const topo = buildTopology(config);
  const t = train({ block: 'DOWN-B4', offsetM: 100, travelSign: -1 });
  stepTrains({ topology: topo, simulation: sim, zones: zones(), trains: [t], dtSec: 1, skipTrainIds: ['T1'] });
  assert.equal(t.offsetM, 100);
});
```

`state.test.js` additions:

```js
assert.ok(snap.routes.wrongLine);
assert.equal(snap.routes.wrongLine.active, null);
assert.ok(snap.routes.wrongLine.eligibility.T1);
assert.ok(Number.isFinite(snap.trains[0].physicalM));
assert.equal(snap.trains[1].travelSign, -1);
```

**Step 2: Implement state integration.**

In `state.js`:

```js
import { makeWrongLine } from './wrong_line.js';
import { blockOffsetToPhysical } from './geometry.js';
```

After the meets scheduler:

```js
wrongLine = makeWrongLine({
  topology: topo,
  trains,
  zones,
  config,
  hasActiveHazard: (id) => Boolean(blockHazards[id]?.active),
  isMeetActive: () => Boolean(meets?.snapshot().active),
});
```

Add `let wrongLine = null;`.

Initialize the direction fields when trains are created so a line change cannot flip them:

```js
travelSign: t.line === 'DOWN' ? -1 : 1,
operationalSign: 1,
```

In `fleetSnapshot`, before `outTrains`:

```js
for (const t of trains) {
  const physical = Number.isFinite(t.physicalM) && t.routePhase
    ? t.physicalM
    : blockOffsetToPhysical(topo, t.line, t.block, t.offsetM);
  t.physicalM = physical;
  t.travelSign = Number.isFinite(t.travelSign) ? t.travelSign : (t.line === 'DOWN' ? -1 : 1);
  t.crossingProgress = t.routePhase === 'CROSS_ENTRY' || t.routePhase === 'CROSS_EXIT'
    ? (wrongLine.snapshot().active?.crossingProgress ?? 0)
    : 0;
  t.crossoverId = t.routePhase === 'CROSS_ENTRY'
    ? wrongLine.snapshot().active?.entryCrossover
    : t.routePhase === 'CROSS_EXIT'
      ? wrongLine.snapshot().active?.exitCrossover
      : null;
  t.targetLine = t.routePhase === 'CROSS_ENTRY'
    ? wrongLine.snapshot().active?.destinationLine
    : t.routePhase === 'CROSS_EXIT'
      ? wrongLine.snapshot().active?.originalLine
      : null;
}
```

Add to snapshot:

```js
routes: {
  active: routes.activeRoute(),
  available: routes.list(),
  wrongLine: wrongLine ? wrongLine.snapshot() : { active: null, eligibility: {} },
},
```

`blocks` output already spreads `b`, so `reservedBy` is included.

In `tick`:

```js
function tick(dtSec) {
  if (!topo || !comm.mqttConnected) return [];
  tickCount += 1;
  if (meets) meets.tick(dtSec);
  const routeEvents = wrongLine ? wrongLine.tick(dtSec) : [];
  routes.tick();
  const aspects = deriveBlockAspects({ topology: topo, blocks: topo.blocks, zones, blockHazards, lookaheadBlocks: sim.lookaheadBlocks });
  stepTrains({ topology: topo, simulation: sim, zones, trains, dtSec, aspects, blockHazards, skipTrainIds: wrongLine ? wrongLine.skipIds() : [] });
  occupyBlocks(topo, trains);
  if (wrongLine) wrongLine.afterStep();
  for (const type of routeEvents) lastEvent = type;
  return routeEvents.map((type) => ({ type, ...(wrongLine?.snapshot().active || {}), time: new Date().toISOString() }));
}
```

Add methods:

```js
function requestWrongLine({ trainId }) {
  if (!wrongLine) return { ok: false, reason: 'wrong-line unavailable' };
  const result = wrongLine.request({ trainId });
  if (result.ok) lastEvent = 'WRONG_LINE_GRANTED';
  return result;
}
function cancelWrongLine({ trainId }) {
  if (!wrongLine) return { ok: false, reason: 'wrong-line unavailable' };
  const result = wrongLine.cancel({ trainId });
  if (result.ok) lastEvent = 'WRONG_LINE_CANCELLED';
  return result;
}
function getWrongLine() {
  return wrongLine ? wrongLine.snapshot() : { active: null, eligibility: {}, lastEvent: null };
}
```

Export them.

**Step 3: Implement simulation changes.**

`occupyBlocks`:

```js
export function occupyBlocks(topology, trains) {
  for (const b of topology.blocks) b.occupiedBy = null;
  for (const t of trains) {
    const line = topology.lines.find((l) => l.id === t.line);
    const n = line.blocks.length;
    let idx = line.blocks.indexOf(t.block);
    let remaining = t.lengthM;
    let first = true;
    const direction = t.operationalSign === -1 ? -1 : 1;
    while (remaining > 0) {
      const block = topology.blocks.find((b) => b.id === line.blocks[idx]);
      block.occupiedBy = t.id;
      if (first) {
        remaining -= direction > 0 ? block.lengthM - t.offsetM : t.offsetM;
        first = false;
      } else {
        remaining -= block.lengthM;
      }
      idx = (idx + direction + n) % n;
      if (remaining <= 0) break;
    }
  }
}
```

This preserves the existing forward convention (`offsetM: 280, lengthM: 60` marks B0 then B1) and mirrors it for reverse movement. The reverse test at B1 offset 40 marks B1 then B0, not B2.

`stepTrains`:

```js
export function stepTrains({ topology, simulation, zones, trains, dtSec, aspects, blockHazards = {}, skipTrainIds = [] }) {
  const skip = new Set(skipTrainIds);
  for (const t of trains) {
    if (skip.has(t.id)) continue;
    // ... existing body ...
  }
  return trains;
}
```

**Step 4: Validate wrong-line requests.**

In `validate.js`:

```js
export function validateWrongLineRequest(body, { trainIds = [] } = {}) {
  const trainId = String(body?.trainId || '');
  const request_id = String(body?.request_id || '');
  const errors = [];
  if (!request_id) errors.push('request_id required');
  if (!trainIds.includes(trainId)) errors.push('unknown train');
  if (errors.length) return { ok: false, reason: errors.join('; ') };
  return { ok: true, value: { request_id, trainId } };
}
```

**Step 5: Add the API router.**

Create `backend/src/routes/wrong_line.js`:

```js
import { Router } from 'express';
import { hasPermission } from '../rbac.js';
import { validateWrongLineRequest } from '../validate.js';

export function wrongLineRouter({ auth, config, state, bus, audit, replay }) {
  const router = Router();
  const trainIds = (config.trains || []).map((t) => t.id);
  router.get('/api/routes/wrong-line', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'state:read')) return res.status(403).json({ error: 'forbidden' });
    return res.json(state.getWrongLine());
  });
  router.post('/api/routes/wrong-line', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'route:set')) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE', result: 'FORBIDDEN', reason: 'missing route:set', source: 'rest' });
      return res.status(403).json({ error: 'forbidden' });
    }
    const check = validateWrongLineRequest(req.body, { trainIds });
    if (!check.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE', result: 'REJECTED', reason: check.reason, source: 'rest' });
      return res.status(400).json({ error: 'invalid wrong-line request', reason: check.reason });
    }
    const dedupe = replay.check(check.value.request_id, { username: req.user.username, action: 'WRONG_LINE' });
    if (!dedupe.ok) return res.status(400).json({ error: 'duplicate', reason: dedupe.reason });
    const applied = state.requestWrongLine(check.value);
    if (!applied.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE', target: check.value.trainId, result: 'REJECTED', reason: applied.reason, source: 'rest' });
      return res.status(409).json({ error: 'wrong-line rejected', reason: applied.reason });
    }
    audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE', target: check.value.trainId, result: 'ACCEPTED', source: 'rest' });
    bus.event({ type: 'WRONG_LINE_GRANTED', trainId: check.value.trainId, actor: req.user.username });
    return res.json({ ok: true, route: applied.route, state: bus.snapshot() });
  });
  router.post('/api/routes/wrong-line/cancel', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'route:set')) return res.status(403).json({ error: 'forbidden' });
    const check = validateWrongLineRequest(req.body, { trainIds });
    if (!check.ok) return res.status(400).json({ error: 'invalid cancel', reason: check.reason });
    const applied = state.cancelWrongLine(check.value);
    if (!applied.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE_CANCEL', target: check.value.trainId, result: 'REJECTED', reason: applied.reason, source: 'rest' });
      return res.status(409).json({ error: 'cancel rejected', reason: applied.reason });
    }
    audit.write({ actor: req.user.username, role: req.user.role, action: 'WRONG_LINE_CANCEL', target: check.value.trainId, result: 'ACCEPTED', source: 'rest' });
    bus.event({ type: 'WRONG_LINE_CANCELLED', trainId: check.value.trainId, actor: req.user.username });
    return res.json({ ok: true, state: bus.snapshot() });
  });
  return router;
}
```

Mount in `app.js` after JSON:

```js
import { wrongLineRouter } from './routes/wrong_line.js';
app.use(wrongLineRouter(deps));
```

**Step 6: Publish lifecycle events in the loop.**

```js
function step() {
  const events = state.tick(dtSec);
  for (const event of events || []) bus.event(event);
  return bus.snapshot();
}
```

**Step 7: Run tests.**

```bash
npm --prefix backend test -- test/wrong_line.test.js test/wrong_line_api.test.js test/state.test.js test/simulation.test.js test/control_routes.test.js
```

Expected: PASS. If `control_routes.test.js` expects old crossover IDs, update to `X-A`/`X-B` and expect the legacy `/api/route` still available.

## Task 9: Make meets hold-only

**Files:**
- Modify: `backend/src/meets.js`
- Modify: `backend/test/meets.test.js`
- Modify: `backend/src/state.js` if it still passes `routes`

**Step 1: Update tests.**

In `meets.test.js`, remove the crossover/route grant expectations and assert the holder is released without a route:

```js
test('meet holds the holder and releases without a crossover', () => {
  // existing setup with crossoverChance 0
  // ... run to HOLDING ...
  assert.equal(world.holder.commandedSpeedKmh, 0);
  // after hold expires:
  assert.equal(world.holder.commandedSpeedKmh, null);
  assert.equal(world.routes.calls.length, 0);
});
```

**Step 2: Simplify `meets.js`.**

- In `beginHold`, set `crossover: false`, `routeId: null`, and remove the RNG crossover selection.
- Delete the `if (active.crossover && !active.routeId)` block and the entire `CROSSING` phase.
- In `HOLDING`, when `holdRemaining <= 0 && !restricted`, release the hold, `record('HELD')`, and `toIdle()`.
- Keep `crossoverChance: 0` in the snapshot config for compatibility.
- Keep the `routes` parameter but never call `requestRoute`.

**Step 3: Run.**

```bash
npm --prefix backend test -- test/meets.test.js
```

Expected: PASS.

## Task 10: Godot state-driven route crossings and HUD

**Files:**
- Modify: `godot/src/fleet_controller.gd`
- Modify: `godot/src/twin_hud.gd`
- Modify: `godot/tests/test_crossover_visual.gd`
- Create: `godot/tests/test_wrong_line_visual.gd`
- Create: `godot/tests/test_wrong_line_hud.gd`
- Modify: `godot/tests/capture_crossover.gd`

**Step 1: Write failing tests.**

`test_wrong_line_visual.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var fleet := scene.get_node("FleetController") as FleetController
	var scenery := scene.get_node("Scenery") as SceneryDirector
	var state := {
		"trains": [
			{"id": "T1", "line": "DOWN", "block": "DOWN-B4", "offsetM": 125.77, "physicalM": 120.0, "travelSign": 1, "speedKmh": 8.3, "targetSpeedKmh": 8.3, "routePhase": "CROSS_ENTRY", "crossingProgress": 0.5, "crossoverId": "CrossoverA", "targetLine": "DOWN"},
			{"id": "T3", "line": "DOWN", "block": "DOWN-B3", "offsetM": 0.0, "physicalM": 320.0, "travelSign": -1, "speedKmh": 0.0, "targetSpeedKmh": 0.0}
		],
		"routes": {"wrongLine": {"active": {"trainId": "T1", "phase": "CROSS_ENTRY", "entryCrossover": "X-A", "exitCrossover": "X-B", "crossingProgress": 0.5, "heldTrainId": "T3"}}}
	}
	fleet.apply_state(state)
	a.ok(fleet.is_train_crossing_over("T1"), "route entry starts a blend")
	a.ok(scenery.is_crossover_active("CrossoverA"), "entry blade is active")
	var t1 := fleet.get_train("T1") as LTSTrain
	a.ok(t1 != null and t1._blend_target_track != null, "T1 is blending toward DOWN during entry")

	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "DOWN", "block": "DOWN-B4", "offsetM": 125.77, "physicalM": 120.0, "travelSign": 1, "speedKmh": 8.3, "targetSpeedKmh": 8.3, "routePhase": "WRONG_LINE", "crossingProgress": 0.0},
			{"id": "T3", "line": "DOWN", "block": "DOWN-B3", "offsetM": 0.0, "physicalM": 320.0, "travelSign": -1, "speedKmh": 0.0, "targetSpeedKmh": 0.0}
		]
	})
	a.ok(not fleet.is_train_crossing_over("T1"), "entry blend ends on WRONG_LINE")
	a.eq(fleet.get_train_line("T1"), "DOWN", "T1 is on DOWN during the wrong-line phase")

	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "DOWN", "block": "DOWN-B4", "offsetM": 0.0, "physicalM": 240.0, "travelSign": 1, "speedKmh": 8.3, "targetSpeedKmh": 8.3, "routePhase": "CROSS_EXIT", "crossingProgress": 0.5, "crossoverId": "CrossoverB", "targetLine": "UP"},
			{"id": "T3", "line": "DOWN", "block": "DOWN-B3", "offsetM": 0.0, "physicalM": 320.0, "travelSign": -1, "speedKmh": 0.0, "targetSpeedKmh": 0.0}
		]
	})
	a.ok(fleet.is_train_crossing_over("T1"), "exit starts a blend")
	a.ok(scenery.is_crossover_active("CrossoverB"), "exit blade is active")

	scene.queue_free()
	await process_frame
	quit(a.report("test_wrong_line_visual"))
```

`test_wrong_line_hud.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame
	var hud := scene.get_node("HUD") as TwinHUD
	hud.apply_state({
		"routes": {"wrongLine": {"active": {"trainId": "T1", "phase": "WRONG_LINE", "entryCrossover": "X-A", "exitCrossover": "X-B", "progress": 0.42, "heldTrainId": "T3"}}},
		"meets": {"enabled": false, "phase": "IDLE", "nextMeetInSec": 0}
	})
	hud.refresh()
	a.ok(hud._status.text.contains("WRONG-LINE"), "HUD shows wrong-line status")
	a.ok(hud._metrics.text.contains("T1") and hud._metrics.text.contains("42%"), "HUD shows route progress")
	a.ok(hud._metrics.text.contains("T3 HOLD"), "HUD shows the held train")

	scene.queue_free()
	await process_frame
	quit(a.report("test_wrong_line_hud"))
```

**Step 2: Implement state-driven crossing.**

In `FleetController`:

```gdscript
var _route_crossings: Dictionary = {}
var _wrong_line: Dictionary = {}

func apply_state(state: Dictionary) -> void:
	var route_var: Variant = state.get("routes", {})
	if route_var is Dictionary:
		var wl: Variant = route_var.get("wrongLine", {})
		if wl is Dictionary:
			_wrong_line = wl
	# inside the per-train loop, after line/block/offset:
	var route_phase := str(item.get("routePhase", ""))
	var crossing_progress := clampf(float(item.get("crossingProgress", 0.0)), 0.0, 1.0)
	var crossover_id := str(item.get("crossoverId", ""))
	var target_line := str(item.get("targetLine", line))
	if route_phase in ["CROSS_ENTRY", "CROSS_EXIT"]:
		_apply_route_crossing(id, target_line, crossing_progress, crossover_id)
		train.set_remote_target(dist_m, speed_kmh, target_kmh)
		_train_blocks[id] = block
```

Implement:

```gdscript
func _apply_route_crossing(train_id: String, to_line: String, progress: float, crossover_id: String) -> void:
	var train := get_train(train_id)
	if not is_instance_valid(train):
		return
	var target: LTSTrack = _registry.track(to_line) if _registry else null
	if not is_instance_valid(target):
		return
	var source_line := get_train_line(train_id)
	if source_line == to_line:
		if _route_crossings.has(train_id):
			var info: Dictionary = _route_crossings[train_id]
			if is_instance_valid(info.get("target_track")):
				train.set_track_blend(info["target_track"], progress)
		return
	_route_crossings[train_id] = {"from_line": source_line, "to_line": to_line, "target_track": target, "crossover_name": crossover_id}
	_crossovers_in_progress[train_id] = {"progress": progress, "duration": 1.0, "target_track": target, "from_line": source_line, "to_line": to_line, "crossover_name": crossover_id}
	var scenery := get_node_or_null("../Scenery")
	if scenery and scenery.has_method("set_crossover_active") and not crossover_id.is_empty():
		scenery.call("set_crossover_active", crossover_id, true)
	train.set_track_blend(target, progress)
```

In `_process`, skip time advancement for route crossings:

```gdscript
for train_id in _crossovers_in_progress:
	if _route_crossings.has(train_id):
		continue
	# existing time-based manual transition
```

When the state phase leaves `CROSS_ENTRY`/`CROSS_EXIT`, finish immediately:

```gdscript
if not route_phase in ["CROSS_ENTRY", "CROSS_EXIT"] and _route_crossings.has(id):
	_finish_route_crossing(id, target_line if target_line != "" else line)
```

Implement:

```gdscript
func _finish_route_crossing(train_id: String, line: String) -> void:
	var info: Dictionary = _route_crossings.get(train_id, {})
	var train := get_train(train_id)
	if is_instance_valid(train):
		var from_line := str(info.get("from_line", ""))
		var target_track: LTSTrack = info.get("target_track")
		if is_instance_valid(target_track) and from_line != line:
			train.clear_track_blend()
			train.set_track(target_track)
		_train_lines[train_id] = line
		var scenery := get_node_or_null("../Scenery")
		if scenery and scenery.has_method("set_crossover_active"):
			scenery.call("set_crossover_active", str(info.get("crossover_name", "")), false)
	_route_crossings.erase(train_id)
	_crossovers_in_progress.erase(train_id)
	_pending_states.erase(train_id)
```

Important: physical position is already in `train.set_remote_target(dist_m...)` after the route block? Do not `continue`; instead call `train.set_remote_target(dist_m, speed_kmh, target_kmh)` and set `_train_lines[id] = line` only after the phase ends. During `CROSS_ENTRY`, `_train_lines` stays source; during `WRONG_LINE`, `_finish_route_crossing` sets it to DOWN.

**Step 3: HUD.**

Add `var _wrong_line: Dictionary = {}` and in `apply_state`:

```gdscript
var routes_var: Variant = state.get("routes")
if routes_var is Dictionary:
	var wrong_var: Variant = routes_var.get("wrongLine")
	if wrong_var is Dictionary:
		_wrong_line = wrong_var
```

Add:

```gdscript
func _wrong_line_text() -> String:
	var active_var: Variant = _wrong_line.get("active")
	if not (active_var is Dictionary) or active_var.is_empty():
		return ""
	var active: Dictionary = active_var
	var phase := str(active.get("phase", ""))
	var progress := int(round(float(active.get("progress", 0.0)) * 100.0))
	return "WRONG-LINE %s  %s  %d%%  %s HOLD" % [
		str(active.get("trainId", "?")),
		phase,
		progress,
		str(active.get("heldTrainId", "?")),
	]
```

Append `_wrong_line_text()` to `_metrics.text`, and include it in `_status.text` so the headless test can find it.

**Step 4: Update `test_crossover_visual.gd`.**

Replace old `UP-B2` / `DOWN-B2` with `UP-B0` / `DOWN-B4`, and keep the manual time-based transition for `transition_train_line`. The backend-driven section now sends `routePhase: "CROSS_ENTRY"` with `crossingProgress`; assert that combination instead of a raw line change. The old raw-line-change behavior should remain for compatibility only when no route fields are present.

**Step 5: Run.**

```bash
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_wrong_line_visual.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_wrong_line_hud.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_crossover_visual.gd
```

Expected: PASS.

## Task 11: Web operator UI, auth and endpoint fixes

**Files:**
- Modify: `web/src/App.tsx`
- Modify: `web/src/styles.css` if a new card/login needs it
- Modify: `web/package.json` only if a new dependency is required (avoid)

**Step 1: Add token/auth plumbing.**

Replace the bare `api()` helper with:

```tsx
const [token, setToken] = useState<string>(() => localStorage.getItem('railway_token') || '');
const [username, setUsername] = useState('operator');
const [password, setPassword] = useState('operator-dev-pass');

async function login() {
  const r = await fetch(`${API}/api/auth/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  if (!r.ok) throw new Error('Login failed');
  const body = await r.json();
  localStorage.setItem('railway_token', body.token);
  setToken(body.token);
}

async function api(path: string, body?: unknown) {
  const r = await fetch(`${API}${path}`, {
    method: body ? 'POST' : 'GET',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!r.ok) {
    const err = await r.json().catch(() => ({}));
    throw new Error(err.reason || err.error || 'Request failed');
  }
  return r.json();
}
```

Render a login form when `!token`. Do not hardcode production credentials; the default form value is the dev seed user.

**Step 2: Fix control endpoints.**

```tsx
async function command(event: string) {
  try {
    await api('/api/control', {
      request_id: crypto.randomUUID(),
      zone: 'zone1',
      event,
      timestamp: new Date().toISOString(),
      source: 'dashboard',
      payload: {},
    });
    await refresh();
  } catch (e) { setError(String(e)); }
}

async function requestWrongLine(trainId: string) {
  try {
    await api('/api/routes/wrong-line', { request_id: crypto.randomUUID(), trainId });
    await refresh();
  } catch (e) { setError(String(e)); }
}

async function cancelWrongLine(trainId: string) {
  try {
    await api('/api/routes/wrong-line/cancel', { request_id: crypto.randomUUID(), trainId });
    await refresh();
  } catch (e) { setError(String(e)); }
}
```

Keep `/api/speed` for the selected train.

**Step 3: Extend types and render the route card.**

```tsx
type WrongLine = {
  active: null | {
    trainId: string; routeId: string; phase: string; progress: number;
    entryCrossover: string; exitCrossover: string; heldTrainId: string;
  };
  eligibility: Record<string, { eligible: boolean; reason: string | null; distanceToEntryM: number }>;
};

type State = {
  // existing fields...
  routes?: {
    activeRoute?: { routeId: string; trainId: string; from: string; to: string } | null;
    wrongLine?: WrongLine;
  };
};
```

Render above the block diagram:

```tsx
const wrongLine = state.routes?.wrongLine;
const wlActive = wrongLine?.active;
const wlElig = wrongLine?.eligibility?.[selectedTrain];

<section className="panel">
  <div className="panel-head">
    <div><div className="eyebrow">INTERLOCKED ROUTE</div><h3>Wrong-Line Run</h3></div>
    <ArrowRightLeft size={19} />
  </div>
  <div className="route-grid">
    <div><small>Train</small><b>{selectedTrain}</b></div>
    <div><small>Eligibility</small><b>{wlElig?.eligible ? 'READY' : (wlElig?.reason || 'UNKNOWN')}</b></div>
    <div><small>Distance to entry</small><b>{wlElig?.distanceToEntryM ?? '—'} m</b></div>
    <div><small>Phase</small><b>{wlActive?.phase || 'IDLE'}</b></div>
    <div><small>Progress</small><b>{wlActive ? `${Math.round(wlActive.progress * 100)}%` : '—'}</b></div>
    <div><small>Held</small><b>{wlActive?.heldTrainId || '—'}</b></div>
  </div>
  <div className="button-row">
    <button className="primary" disabled={!wlElig?.eligible || !!wlActive} onClick={() => requestWrongLine(selectedTrain)}>Start wrong-line run</button>
    <button className="secondary" disabled={!wlActive || wlActive.phase !== 'APPROACH'} onClick={() => cancelWrongLine(selectedTrain)}>Cancel approach</button>
  </div>
</section>
```

Add a status line to each train card: `{t.travelSign === -1 ? 'ANTICLOCKWISE' : 'CLOCKWISE'}`.

Remove the old "Route T1 (UP → DOWN)" buttons or disable them; they use the retired `/api/route` flow.

**Step 4: Run the build.**

```bash
npm --prefix web run build
```

Expected: PASS with no TypeScript errors.

## Task 12: Phase 2 gate

**Step 1: Run all suites.**

```bash
bash godot/tests/run_tests.sh
MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test
pio test -e native --project-dir esp32
npm --prefix web run build
```

**Step 2: Live acceptance.**

Start the broker/backend/Godot/web using the existing compose tooling. With the web operator UI:
- select T1; confirm eligibility is READY around physical 40–80 m before A;
- start; confirm the route phase advances through APPROACH, CROSS_ENTRY, WRONG_LINE, CROSS_EXIT, CLEARANCE, DONE;
- confirm T3 is held at DOWN physical 320 and visibly stops before B;
- confirm T1 crosses at A, runs 120 m, crosses at B, and the section stays reserved until the rear clears;
- confirm no snap/freeze and that T3 resumes after DONE.

**Step 3: Capture and record.**

Run `capture_crossover.gd` at 1440×900, save before/mid/after stills under `/tmp/opencode`, and add the paths and test counts to `docs/porting/acceptance.md`.

---

# Phase 3 — Sensor-Slow, Camera-Confirm, Stop

## Task 13: FastAPI ML service

**Files:**
- Create: `ml/app.py`
- Create: `ml/detector.py`
- Create: `ml/requirements.txt`
- Create: `ml/README.md`
- Create: `ml/tests/test_detector.py`
- Create: `ml/tests/test_api.py`
- Modify: `.gitignore`

**Step 1: Add ignore rules.**

Append to `.gitignore`:

```gitignore
ml/.cache/
```

**Step 2: Write the failing ML tests.**

`ml/tests/test_detector.py`:

```python
import os
os.environ["ML_STUB"] = "1"
from detector import WildlifeDetector

def test_stub_returns_one_animal_detection():
    detector = WildlifeDetector(stub=True)
    result = detector.detect(b"not-a-real-jpeg")
    assert result["model"] == "stub"
    assert len(result["detections"]) == 1
    det = result["detections"][0]
    assert det["label"] in {
        "bird", "cat", "dog", "horse", "sheep", "cow",
        "elephant", "bear", "zebra", "giraffe",
    }
    assert 0.0 <= det["confidence"] <= 1.0
    assert len(det["box"]) == 4

def test_stub_is_deterministic():
    detector = WildlifeDetector(stub=True)
    assert detector.detect(b"x") == detector.detect(b"x")
```

`ml/tests/test_api.py`:

```python
import os
os.environ["ML_STUB"] = "1"
from fastapi.testclient import TestClient
from app import app

client = TestClient(app)

def test_health_reports_stub():
    res = client.get("/health")
    assert res.status_code == 200
    body = res.json()
    assert body["ok"] is True
    assert body["stub"] is True
    assert body["modelLoaded"] is True

def test_detect_rejects_empty_body():
    res = client.post("/detect", content=b"", headers={"content-type": "image/jpeg"})
    assert res.status_code == 400

def test_detect_returns_detections():
    res = client.post("/detect", content=b"jpeg-bytes", headers={"content-type": "image/jpeg"})
    assert res.status_code == 200
    body = res.json()
    assert body["model"] == "stub"
    assert body["detections"]
```

**Step 3: Implement `detector.py`.**

```python
import io
import os
import time

ANIMAL_LABELS = {
    "bird", "cat", "dog", "horse", "sheep", "cow",
    "elephant", "bear", "zebra", "giraffe",
}

class WildlifeDetector:
    def __init__(self, stub=None, device=None, min_confidence=None):
        self.stub = os.getenv("ML_STUB", "0") == "1" if stub is None else bool(stub)
        self.device = device or os.getenv("ML_DEVICE", "cpu")
        self.min_confidence = float(min_confidence if min_confidence is not None else os.getenv("ML_MIN_CONFIDENCE", "0.5"))
        self._model = None
        self._labels = None

    @property
    def model_loaded(self):
        if self.stub:
            return True
        try:
            self._load()
            return True
        except Exception:
            return False

    def _load(self):
        if self._model is not None:
            return
        import torch
        import torchvision
        from torchvision.models.detection import SSDLite320_MobileNet_V3_Large_Weights
        weights = SSDLite320_MobileNet_V3_Large_Weights.DEFAULT
        model = torchvision.models.detection.ssdlite320_mobilenet_v3_large(weights=weights)
        model.eval()
        model.to(self.device)
        self._model = model
        self._labels = weights.meta["categories"]

    def detect(self, image_bytes):
        if not image_bytes:
            raise ValueError("empty image")
        if self.stub:
            return {
                "model": "stub",
                "detections": [{
                    "label": "elephant",
                    "confidence": 0.92,
                    "box": [0.32, 0.34, 0.72, 0.78],
                }],
                "latencyMs": 1,
            }
        import torch
        from PIL import Image
        from torchvision.transforms.functional import pil_to_tensor
        self._load()
        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        tensor = pil_to_tensor(image).float().div(255.0).unsqueeze(0).to(self.device)
        started = time.time()
        with torch.no_grad():
            output = self._model(tensor)[0]
        detections = []
        for label_id, score, box in zip(output["labels"].tolist(), output["scores"].tolist(), output["boxes"].tolist()):
            label = self._labels[label_id]
            if label not in ANIMAL_LABELS or score < self.min_confidence:
                continue
            width, height = image.size
            detections.append({
                "label": label,
                "confidence": round(float(score), 4),
                "box": [box[0] / width, box[1] / height, box[2] / width, box[3] / height],
            })
        detections.sort(key=lambda d: d["confidence"], reverse=True)
        return {
            "model": "ssdlite320_mobilenet_v3_large",
            "detections": detections,
            "latencyMs": int((time.time() - started) * 1000),
        }
```

**Step 4: Implement `app.py`.**

```python
import logging
import os
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from detector import WildlifeDetector

logging.basicConfig(level=logging.INFO)
app = FastAPI(title="Railway Wildlife Detector")
detector = WildlifeDetector()

@app.get("/health")
def health():
    return {
        "ok": True,
        "stub": detector.stub,
        "modelLoaded": detector.model_loaded,
        "model": "stub" if detector.stub else "ssdlite320_mobilenet_v3_large",
        "device": detector.device,
    }

@app.post("/detect")
async def detect(request: Request):
    body = await request.body()
    if not body:
        return JSONResponse({"error": "empty image"}, status_code=400)
    if len(body) > 1_000_000:
        return JSONResponse({"error": "image too large"}, status_code=413)
    try:
        result = detector.detect(body)
    except ValueError as exc:
        return JSONResponse({"error": str(exc)}, status_code=400)
    except Exception as exc:
        logging.exception("detector failed")
        return JSONResponse({"error": "model unavailable", "detail": str(exc)}, status_code=503)
    logging.info("detect model=%s detections=%d latencyMs=%s", result["model"], len(result["detections"]), result.get("latencyMs"))
    return result
```

`requirements.txt`:

```text
fastapi==0.135.1
uvicorn==0.41.0
torch==2.10.0
torchvision==0.25.0
pillow==12.1.1
numpy==2.2.6
pytest==9.0.2
httpx==0.28.1
```

`.gitignore` already ignores `ml/.cache/`; no model artifacts are committed.

**Step 5: Run tests.**

```bash
cd ml && ML_STUB=1 python -m pytest tests -q
```

Expected: PASS without downloading weights.

**Step 6: Real-model smoke test (optional, manual).**

```bash
cd ml && uvicorn app:app --port 8001
curl -s http://127.0.0.1:8001/health
```

If weights are unavailable, `/health` reports `modelLoaded: false` and `/detect` returns 503. That is the intended degraded behavior; do not block the suite on it.

## Task 14: Backend staged hazards and stage-aware aspects

**Files:**
- Modify: `backend/src/state.js`
- Modify: `backend/src/signalling.js`
- Modify: `backend/src/simulation.js`
- Modify: `backend/test/wildlife_observation.test.js`
- Modify: `backend/test/signalling.test.js`
- Modify: `backend/test/simulation.test.js`

**Step 1: Write failing tests.**

In `wildlife_observation.test.js`:

```js
test('sensor evidence is SUSPECTED, camera confirmation is CONFIRMED', () => {
  const deps = buildDeps();
  const now = Date.now();
  deps.state.applyWildlifeObservation({
    eventId: 's1', source: 'trackside', line: 'UP', distanceM: 100,
    wildlifeDetected: true, species: 'deer', count: 1, sensorId: 'UP-S0', timestamp: now,
  });
  let snap = deps.state.snapshot();
  let hazard = snap.blocks.find((b) => b.id === 'UP-B0').hazard;
  assert.equal(hazard.stage, 'SUSPECTED');
  assert.equal(hazard.confirmed, false);
  assert.deepEqual(hazard.sensorSources, ['trackside']);
  assert.equal(snap.blocks.find((b) => b.id === 'UP-B0').signal, 'YELLOW');

  deps.state.applyCameraConfirmation({
    line: 'UP', blockId: 'UP-B0', trainId: 'T1', species: 'elephant',
    confidence: 0.91, bbox: [0.1, 0.2, 0.5, 0.6], model: 'stub',
  });
  snap = deps.state.snapshot();
  hazard = snap.blocks.find((b) => b.id === 'UP-B0').hazard;
  assert.equal(hazard.stage, 'CONFIRMED');
  assert.equal(hazard.confirmed, true);
  assert.equal(hazard.confidence, 0.91);
  assert.equal(hazard.camera.trainId, 'T1');
  assert.equal(snap.blocks.find((b) => b.id === 'UP-B0').signal, 'RED');
  assert.equal(snap.trains[0].targetSpeedKmh, 0);

  deps.state.applyWildlifeObservation({
    eventId: 's2', source: 'trackside', line: 'UP', distanceM: 100,
    wildlifeDetected: false, species: 'deer', count: 0, sensorId: 'UP-S0', timestamp: now + 1000,
  });
  snap = deps.state.snapshot();
  hazard = snap.blocks.find((b) => b.id === 'UP-B0').hazard;
  assert.equal(hazard.stage, 'CONFIRMED', 'confirmation stays latched after sensors clear');

  deps.state.applyCommand({ zone: 'zone1', event: 'RESET' });
  snap = deps.state.snapshot();
  hazard = snap.blocks.find((b) => b.id === 'UP-B0').hazard;
  assert.equal(hazard.stage, 'NONE');
  assert.equal(hazard.confirmed, false);
  assert.equal(snap.zones.zone1.status, 'NORMAL');
});
```

`signalling.test.js`:

```js
assert.equal(aspects['UP-B0'], 'YELLOW'); // SUSPECTED
assert.equal(aspects['UP-B0'], 'RED');    // CONFIRMED
```

`simulation.test.js`:

```js
test('SUSPECTED caps at caution and CONFIRMED stops', () => {
  const topo = buildTopology(config);
  const t = train({ block: 'UP-B0', offsetM: 0, speedKmh: 48 });
  stepTrains({
    topology: topo, simulation: sim, zones: zones(), trains: [t], dtSec: 1,
    blockHazards: { 'UP-B0': { stage: 'SUSPECTED', active: true } },
  });
  assert.ok(t.targetSpeedKmh <= 30);
  t.speedKmh = 20;
  stepTrains({
    topology: topo, simulation: sim, zones: zones(), trains: [t], dtSec: 1,
    blockHazards: { 'UP-B0': { stage: 'CONFIRMED', active: true } },
  });
  assert.equal(t.targetSpeedKmh, 0);
});
```

**Step 2: Implement the hazard shape.**

In `state.js`, replace `blockHazards[b.id] = {...}`:

```js
blockHazards[b.id] = {
  blockId: b.id,
  line: b.line,
  zone: b.zone,
  stage: 'NONE',
  confirmed: false,
  confidence: null,
  confirmedAt: null,
  confirmedBy: null,
  model: null,
  camera: null,
  evidence: {
    trackside: null,
    onboardSensor: null,
    camera: null,
  },
  sensorSources: [],
  active: false,
  since: null,
};
```

**Step 3: Rewrite `applyWildlifeObservation` evidence handling.**

```js
const slot = obs.source === 'trackside' ? 'trackside'
  : (obs.source === 'onboard-sensor' || obs.source === 'onboard-camera') ? 'onboardSensor'
  : 'trackside';

const prevActive = hazard.active;
if (obs.wildlifeDetected) {
  hazard.evidence[slot] = {
    active: true,
    species: obs.species,
    count: obs.count,
    eventId: obs.eventId,
    at: obs.timestamp,
    ...(obs.sensorId ? { sensorId: obs.sensorId } : {}),
    ...(obs.trainId ? { trainId: obs.trainId, confidence: obs.confidence } : {}),
  };
} else if (hazard.evidence[slot]) {
  hazard.evidence[slot] = { ...hazard.evidence[slot], active: false, at: obs.timestamp };
}

hazard.sensorSources = Object.entries(hazard.evidence)
  .filter(([key, value]) => key !== 'camera' && value?.active)
  .map(([key]) => key);

const sensorActive = hazard.sensorSources.length > 0;
hazard.active = hazard.confirmed || sensorActive;
hazard.stage = hazard.confirmed ? 'CONFIRMED' : sensorActive ? 'SUSPECTED' : 'NONE';

if (hazard.active && !prevActive) {
  hazard.since = new Date().toISOString();
  lastEvent = 'WILDLIFE_DETECTED';
} else if (!hazard.active && prevActive) {
  const z = zones[hazard.zone];
  if (z && z.sensorHealthy && z.status !== 'SENSOR_FAULT') z.status = 'RECOVERY_REQUIRED';
  lastEvent = 'WILDLIFE_CLEARED';
}
```

When `sensorActive`, set the zone:

```js
if (sensorActive) {
  const z = zones[hazard.zone];
  if (z) {
    z.wildlifeDetected = true;
    if (z.sensorHealthy) z.status = 'HAZARD';
    z.targetSpeedKmh = hazard.stage === 'CONFIRMED' ? 0 : sim.cautionSpeedKmh ?? 30;
  }
}
```

Do not let a sensor clear a latched confirmation.

**Step 4: Add `applyCameraConfirmation`.**

```js
function applyCameraConfirmation({ line, blockId, trainId, species, confidence, bbox, model, capturedAt }) {
  const hazard = blockHazards[blockId];
  if (!hazard) return { ok: false, reason: `unknown block ${blockId}` };
  if (hazard.line !== line) return { ok: false, reason: 'line/block mismatch' };
  if (!hazard.active && hazard.stage === 'NONE') return { ok: false, reason: 'stale hazard' };
  hazard.confirmed = true;
  hazard.active = true;
  hazard.stage = 'CONFIRMED';
  hazard.confidence = Number(confidence);
  hazard.confirmedAt = capturedAt ? new Date(capturedAt).toISOString() : new Date().toISOString();
  hazard.confirmedBy = trainId;
  hazard.model = model || null;
  hazard.camera = {
    trainId, species, confidence: Number(confidence), bbox: bbox || null,
    at: hazard.confirmedAt, frameId: null,
  };
  const z = zones[hazard.zone];
  if (z) {
    z.wildlifeDetected = true;
    if (z.sensorHealthy) z.status = 'HAZARD';
    z.targetSpeedKmh = 0;
  }
  lastEvent = 'WILDLIFE_CONFIRMED';
  return { ok: true, stage: hazard.stage, blockId };
}
```

Export it.

**Step 5: Update `RESET`.**

In `applyCommand` `RESET`:

```js
case 'RESET': {
  const activeSensor = Object.values(blockHazards).some(
    (h) => h.zone === env.zone && h.sensorSources.length > 0,
  );
  if (z.sensorHealthy && !activeSensor) {
    z.status = 'NORMAL';
    z.targetSpeedKmh = DEFAULT_TARGET;
    z.wildlifeDetected = false;
    for (const h of Object.values(blockHazards)) {
      if (h.zone !== env.zone) continue;
      h.stage = 'NONE';
      h.confirmed = false;
      h.confidence = null;
      h.confirmedAt = null;
      h.confirmedBy = null;
      h.camera = null;
      h.sensorSources = [];
      h.evidence = { trackside: null, onboardSensor: null, camera: null };
      h.active = false;
      h.since = null;
    }
  } else {
    return { ok: false, reason: 'reset rejected: active hazard or sensor fault' };
  }
  break;
}
```

**Step 6: Stage-aware aspects.**

In `signalling.js`:

```js
const hazard = blockHazards[block.id];
if (hazard?.active) {
  aspect = mostRestrictive(aspect, hazard.stage === 'CONFIRMED' ? 'RED' : 'YELLOW');
}
for (let k = 1; k <= 1; k++) {
  const ahead = blockHazards[ids[(i + k) % n]];
  if (ahead?.active) {
    aspect = mostRestrictive(aspect, ahead.stage === 'CONFIRMED' ? 'YELLOW' : 'YELLOW');
    break;
  }
}
if (block.reservedBy) aspect = mostRestrictive(aspect, 'RED');
```

`zoneSignal`:

```js
const confirmed = Object.values(blockHazards).some((h) => h.zone === zoneId && h.stage === 'CONFIRMED');
if (confirmed) return 'RED';
const suspected = Object.values(blockHazards).some((h) => h.zone === zoneId && h.stage === 'SUSPECTED');
if (suspected) return 'YELLOW';
```

Keep the existing recovery/sensor rules.

**Step 7: Stage-aware speed.**

In `simulation.js`:

```js
export function stepTrains({ topology, simulation, zones, trains, dtSec, aspects, blockHazards = {}, skipTrainIds = [] }) {
  const skip = new Set(skipTrainIds);
  for (const t of trains) {
    if (skip.has(t.id)) continue;
    // ... existing zone/status/target ...
    const ownHazard = blockHazards[t.block];
    if (ownHazard?.active) {
      if (ownHazard.stage === 'CONFIRMED') t.targetSpeedKmh = 0;
      else if (ownHazard.stage === 'SUSPECTED') t.targetSpeedKmh = Math.min(t.targetSpeedKmh, simulation.cautionSpeedKmh ?? 30);
    }
    // ... existing acceleration/advance ...
  }
}
```

Pass `blockHazards` from `state.tick`.

**Step 8: Run tests.**

```bash
npm --prefix backend test -- test/wildlife_observation.test.js test/signalling.test.js test/simulation.test.js
```

Expected: PASS.

## Task 15: Backend camera ingest, ML client and confirmation policy

**Files:**
- Modify: `backend/src/config.js`
- Create: `backend/src/ml.js`
- Create: `backend/src/routes/wildlife.js`
- Modify: `backend/src/app.js`
- Modify: `backend/server.js`
- Modify: `backend/test/app_helpers.js`
- Create: `backend/test/camera.test.js`
- Modify: `backend/test/read_routes.test.js`

**Step 1: Add config.**

```js
cameraConfirm: {
  enabled: true,
  minConfidence: 0.5,
  confirmFrames: 2,
  confirmWindowSec: 2,
  cameraRangeM: 200,
  captureFps: 2,
  frameWidth: 640,
  frameHeight: 360,
  jpegQuality: 70,
  evidenceTtlSec: 86400,
},
ml: {
  url: process.env.ML_URL || 'http://127.0.0.1:8001',
  timeoutMs: Number(process.env.ML_TIMEOUT_MS || 2000),
},
cameraIngestToken: process.env.CAMERA_INGEST_TOKEN || 'dev-camera-token',
cameraEvidenceDir: process.env.CAMERA_EVIDENCE_DIR || './data/camera-evidence',
```

Validate ranges in `validateConfig`: confidences `0..1`, `confirmFrames >= 1`, `captureFps > 0`, `jpegQuality 1..100`, token non-empty.

**Step 2: Implement `ml.js`.**

```js
export function makeMlClient({ config, fetchImpl = fetch }) {
  const url = config.ml?.url || 'http://127.0.0.1:8001';
  const timeoutMs = config.ml?.timeoutMs || 2000;
  async function detect(jpeg) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetchImpl(`${url}/detect`, {
        method: 'POST',
        headers: { 'content-type': 'image/jpeg' },
        body: jpeg,
        signal: controller.signal,
      });
      if (!res.ok) throw new Error(`ml status ${res.status}`);
      return await res.json();
    } finally {
      clearTimeout(timer);
    }
  }
  async function health() {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetchImpl(`${url}/health`, { signal: controller.signal });
      if (!res.ok) throw new Error(`ml status ${res.status}`);
      return await res.json();
    } finally {
      clearTimeout(timer);
    }
  }
  return { detect, health };
}
```

**Step 3: Add state methods used by the route.**

```js
function getBlockHazard(blockId) {
  const h = blockHazards[blockId];
  return h ? { ...h, evidence: { ...h.evidence } } : null;
}
function getCameraHealth() {
  return { enabled: Boolean(config.cameraConfirm?.enabled), ml: config.ml?.url || null };
}
```

Export `getBlockHazard` and `getCameraHealth`. `applyCameraConfirmation` is from Task 14.

**Step 4: Implement `routes/wildlife.js`.**

```js
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

export function wildlifeRouter({ config, state, bus, audit, ml }) {
  const router = Router();
  const frameTimes = new Map();
  const streaks = new Map();
  const evidenceDir = config.cameraEvidenceDir || './data/camera-evidence';

  router.get('/api/wildlife/camera/health', async (_req, res) => {
    try {
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
      if (!trainId || !line || !blockId || !eventId) {
        return res.status(400).json({ error: 'missing camera headers' });
      }
      if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
        return res.status(400).json({ error: 'empty jpeg' });
      }
      if (req.body.length > 1_000_000) return res.status(413).json({ error: 'frame too large' });

      const now = Date.now();
      const recent = (frameTimes.get(trainId) || []).filter((t) => now - t < 1000);
      if (recent.length >= (config.cameraConfirm?.captureFps || 2) * 2.5) {
        return res.status(429).json({ error: 'frame rate exceeded' });
      }
      recent.push(now);
      frameTimes.set(trainId, recent);

      const hazard = state.getBlockHazard(blockId);
      if (!hazard || hazard.line !== line || !hazard.active) {
        return res.status(409).json({ ok: false, stale: true, stage: hazard?.stage || 'NONE' });
      }

      let result;
      try {
        result = await ml.detect(req.body);
      } catch (err) {
        bus.alert({ source: 'ml', severity: 'MEDIUM', message: 'ML unavailable; hazard remains SUSPECTED', timestamp: new Date().toISOString() });
        return res.json({ ok: true, confirmed: false, degraded: true, stage: 'SUSPECTED' });
      }

      const detections = (result.detections || []).filter((d) => d.confidence >= (config.cameraConfirm?.minConfidence ?? 0.5));
      const best = detections[0] || null;
      const key = `${eventId}:${blockId}`;
      if (!best) {
        streaks.delete(key);
        return res.json({ ok: true, confirmed: false, degraded: false, stage: hazard.stage, detection: null });
      }

      const windowMs = (config.cameraConfirm?.confirmWindowSec ?? 2) * 1000;
      const previous = streaks.get(key);
      let streak = 1;
      if (previous && now - previous.at <= windowMs) streak = previous.count + 1;
      streaks.set(key, { at: now, count: streak });

      const confirm = streak >= (config.cameraConfirm?.confirmFrames ?? 2);
      if (confirm) {
        state.applyCameraConfirmation({
          line, blockId, trainId, species: best.label,
          confidence: best.confidence, bbox: best.box, model: result.model,
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
        audit.write({ actor: 'camera', role: 'system', action: 'WILDLIFE_CONFIRMED', zone: hazard.zone, target: blockId, result: 'ACCEPTED', source: 'camera' });
        bus.event({ type: 'WILDLIFE_CONFIRMED', trainId, blockId, species: best.label, confidence: best.confidence });
        streaks.delete(key);
        return res.json({ ok: true, confirmed: true, degraded: false, stage: 'CONFIRMED', confidence: best.confidence, species: best.label });
      }

      bus.event({ type: 'WILDLIFE_CAMERA_FRAME', trainId, blockId, confidence: best.confidence, species: best.label });
      return res.json({ ok: true, confirmed: false, degraded: false, stage: hazard.stage, confidence: best.confidence, species: best.label });
    },
  );

  return router;
}
```

Mount in `app.js` **before** `express.json`:

```js
app.use(wildlifeRouter(deps));
app.use(express.json({ limit: '32kb' }));
```

The router only matches the camera paths, so the raw body for `/api/wildlife/camera/frame` is preserved.

**Step 5: Wire `server.js` and test deps.**

```js
import { makeMlClient } from './src/ml.js';
const ml = makeMlClient({ config });
const app = createApp({ config, db, audit, replay, auth, state, bus, events, mqtt, ml });
```

In `app_helpers.js`, provide a fake ML client by default:

```js
const ml = overrides.ml || {
  health: async () => ({ ok: true, stub: true, modelLoaded: true }),
  detect: async () => ({ model: 'stub', detections: [{ label: 'elephant', confidence: 0.92, box: [0.3, 0.3, 0.7, 0.7] }] }),
};
```

Set `config.cameraEvidenceDir` to a temp dir in tests (`fs.mkdtempSync(path.join(os.tmpdir(), 'evidence-'))`).

**Step 6: Write camera tests.**

`backend/test/camera.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildDeps, withServer } from './app_helpers.js';

const headers = (config, extra = {}) => ({
  'content-type': 'image/jpeg',
  'x-camera-token': config.cameraIngestToken,
  'x-train-id': 'T1',
  'x-line': 'UP',
  'x-block': 'UP-B0',
  'x-event-id': 'evt-1',
  'x-captured-at': new Date().toISOString(),
  ...extra,
});

function suspect(deps) {
  deps.state.applyWildlifeObservation({
    eventId: 'evt-1', source: 'trackside', line: 'UP', distanceM: 100,
    wildlifeDetected: true, species: 'deer', count: 1, sensorId: 'UP-S0', timestamp: Date.now(),
  });
}

test('camera endpoint requires the machine token', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    suspect(deps);
    const res = await fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: { ...headers(deps.config), 'x-camera-token': 'wrong' }, body: Buffer.from('jpeg'),
    });
    assert.equal(res.status, 401);
  });
});

test('a single high-confidence frame warns but does not confirm', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    suspect(deps);
    const post = () => fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: headers(deps.config), body: Buffer.from('jpeg'),
    });
    const first = await (await post()).json();
    assert.equal(first.confirmed, false);
    assert.equal(first.stage, 'SUSPECTED');
    let snap = deps.state.snapshot();
    assert.equal(snap.blocks.find((b) => b.id === 'UP-B0').hazard.stage, 'SUSPECTED');
    assert.ok(snap.trains[0].targetSpeedKmh <= 30);

    const second = await (await post()).json();
    assert.equal(second.confirmed, true);
    snap = deps.state.snapshot();
    assert.equal(snap.blocks.find((b) => b.id === 'UP-B0').hazard.stage, 'CONFIRMED');
    assert.equal(snap.trains[0].targetSpeedKmh, 0);
  });
});

test('two consecutive 0.6 frames confirm, one alone does not', async () => {
  const deps = buildDeps({
    ml: {
      health: async () => ({ ok: true }),
      detect: async () => ({ model: 'stub', detections: [{ label: 'elephant', confidence: 0.6, box: [0, 0, 1, 1] }] }),
    },
  });
  await withServer(deps, async (url) => {
    suspect(deps);
    const post = () => fetch(`${url}/api/wildlife/camera/frame`, { method: 'POST', headers: headers(deps.config), body: Buffer.from('jpeg') });
    assert.equal((await (await post()).json()).confirmed, false);
    assert.equal((await (await post()).json()).confirmed, true);
  });
});

test('stale event is rejected without reactivating the hazard', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const res = await fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: headers(deps.config), body: Buffer.from('jpeg'),
    });
    assert.equal(res.status, 409);
  });
});

test('ML failure returns degraded and leaves the hazard SUSPECTED', async () => {
  const deps = buildDeps({
    ml: { health: async () => ({ ok: false }), detect: async () => { throw new Error('down'); } },
  });
  await withServer(deps, async (url) => {
    suspect(deps);
    const res = await fetch(`${url}/api/wildlife/camera/frame`, {
      method: 'POST', headers: headers(deps.config), body: Buffer.from('jpeg'),
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.degraded, true);
    assert.equal(deps.state.snapshot().blocks.find((b) => b.id === 'UP-B0').hazard.stage, 'SUSPECTED');
  });
});
```

**Step 7: Run tests.**

```bash
npm --prefix backend test -- test/camera.test.js test/wildlife_observation.test.js test/read_routes.test.js
```

Expected: PASS.

## Task 16: Godot camera confirmation node and HUD

**Files:**
- Create: `godot/src/camera_confirmation.gd`
- Modify: `godot/src/ltstrain.gd`
- Modify: `godot/src/fleet_controller.gd`
- Modify: `godot/src/twin_hud.gd`
- Create: `godot/tests/test_camera_confirmation.gd`
- Modify: `godot/scenes/lts_full.tscn` only if a node needs explicit wiring; the node is created per train in code.

**Step 1: Write the failing test.**

```gdscript
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var fleet := scene.get_node("FleetController") as FleetController
	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "UP", "block": "UP-B0", "offsetM": 40.0, "physicalM": 40.0, "travelSign": 1, "speedKmh": 30.0, "targetSpeedKmh": 30.0}
		],
		"blocks": [
			{"id": "UP-B0", "line": "UP", "index": 0, "zone": "zone1", "lengthM": 250.7964, "hazard": {"stage": "SUSPECTED", "sources": ["trackside"]}}
		]
	})
	var t1 := fleet.get_train("T1") as LTSTrain
	var cam := t1.get_node_or_null("CameraConfirmation") as CameraConfirmation
	a.ok(cam != null, "CameraConfirmation exists on T1")
	if cam == null:
		quit(a.report("test_camera_confirmation"))
		return
	cam.enabled = true
	a.ok(cam.should_capture(), "capture starts on a nearby SUSPECTED hazard")
	cam.upload_override = func(_url: String, _headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
		a.ok(body.size() > 0, "upload contains JPEG bytes")
		return {"ok": true, "confirmed": false, "degraded": false, "stage": "SUSPECTED"}
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	var bytes := cam.encode_frame(image)
	a.ok(bytes.size() > 0, "frame encodes to JPEG bytes")
	var headers := cam.headers("evt-1", "UP-B0")
	a.ok(headers.has("X-Camera-Token: test-token"), "headers include the token")
	a.ok(headers.has("X-Train-Id: T1"), "headers include the train id")
	var result := cam.handle_response({"ok": true, "confirmed": true, "stage": "CONFIRMED"}, 200)
	a.ok(result.get("confirmed", false), "confirmation response is recorded")
	a.ok(cam.get_last_result().get("confirmed", false), "latest result is exposed to the HUD")

	scene.queue_free()
	await process_frame
	quit(a.report("test_camera_confirmation"))
```

**Step 2: Implement the node.**

Create `godot/src/camera_confirmation.gd`:

```gdscript
class_name CameraConfirmation
extends Node

@export var enabled := true
@export var capture_fps := 2.0
@export var frame_width := 640
@export var frame_height := 360
@export var jpeg_quality := 70
@export var camera_range_m := 200.0
@export var api_url := "http://127.0.0.1:3001"
@export var camera_token := "test-token"

var train: LTSTrain
var upload_override: Callable
var _state: Dictionary = {}
var _viewport: SubViewport
var _camera: Camera3D
var _http: HTTPRequest
var _pending := false
var _accum := 0.0
var _event_seq := 0
var _last_result: Dictionary = {}

func _ready() -> void:
	train = get_parent() as LTSTrain
	api_url = OS.get_environment("BACKEND_HTTP_URL") if not OS.get_environment("BACKEND_HTTP_URL").is_empty() else api_url
	camera_token = OS.get_environment("CAMERA_INGEST_TOKEN") if not OS.get_environment("CAMERA_INGEST_TOKEN").is_empty() else camera_token
	_viewport = SubViewport.new()
	_viewport.name = "CaptureViewport"
	_viewport.size = Vector2i(frame_width, frame_height)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.world_3d = get_viewport().find_world_3d()
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.near = 0.1
	_camera.far = 400.0
	_camera.current = true
	_viewport.add_child(_camera)
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func apply_state(state: Dictionary) -> void:
	_state = state

func _hazard_for_train() -> Dictionary:
	if not is_instance_valid(train):
		return {}
	var blocks: Array = _state.get("blocks", [])
	var line := train.line_id
	for block in blocks:
		if not (block is Dictionary):
			continue
		if str(block.get("line", "")) != line:
			continue
		var hazard: Variant = block.get("hazard")
		if hazard is Dictionary and str(hazard.get("stage", "NONE")) in ["SUSPECTED", "CONFIRMED"]:
			return hazard
	return {}

func should_capture() -> bool:
	if not enabled or _pending:
		return false
	if not is_instance_valid(train) or not is_instance_valid(_camera):
		return false
	if train.get_speed_kmh() <= 0.1:
		return false
	var hazard := _hazard_for_train()
	if hazard.is_empty():
		return false
	if str(hazard.get("stage", "")) == "CONFIRMED":
		return false
	return true

func headers(event_id: String, block_id: String) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: image/jpeg",
		"X-Camera-Token: %s" % camera_token,
		"X-Train-Id: %s" % train.train_id,
		"X-Line: %s" % train.line_id,
		"X-Block: %s" % block_id,
		"X-Event-Id: %s" % event_id,
		"X-Captured-At: %s" % Time.get_datetime_string_from_system(true),
	])

func encode_frame(image: Image) -> PackedByteArray:
	return image.save_jpg_to_buffer(jpeg_quality)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(train) or not is_instance_valid(_camera):
		return
	var source := train.get_forward_camera()
	if is_instance_valid(source):
		_camera.global_transform = source.global_transform
	_accum += delta
	if _accum < 1.0 / capture_fps:
		return
	_accum = 0.0
	if should_capture():
		_capture_once()

func _capture_once() -> void:
	_pending = true
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	var bytes := encode_frame(image)
	var hazard := _hazard_for_train()
	var block_id := train.block_id
	_event_seq += 1
	var event_id := "cam-%s-%d-%d" % [train.train_id, int(Time.get_unix_time_from_system()), _event_seq]
	if upload_override.is_valid():
		var result: Dictionary = upload_override.call(api_url + "/api/wildlife/camera/frame", headers(event_id, block_id), bytes)
		handle_response(result, 200)
		_pending = false
		return
	var err := _http.request_raw(api_url + "/api/wildlife/camera/frame", headers(event_id, block_id), HTTPClient.METHOD_POST, bytes)
	if err != OK:
		_pending = false

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		handle_response(parsed, response_code)

func handle_response(result: Dictionary, status: int) -> Dictionary:
	var merged := result.duplicate()
	merged["status"] = status
	merged["at"] = Time.get_unix_time_from_system()
	_last_result = merged
	return _last_result

func get_last_result() -> Dictionary:
	return _last_result
```

`LTSTrain` owns one:

```gdscript
var camera_confirmation: CameraConfirmation

# in _build_train, after _attach_forward_camera(carriage):
camera_confirmation = CameraConfirmation.new()
camera_confirmation.name = "CameraConfirmation"
camera_confirmation.train = self
add_child(camera_confirmation)

func apply_camera_state(state: Dictionary) -> void:
	if is_instance_valid(camera_confirmation):
		camera_confirmation.apply_state(state)

func get_camera_confirmation() -> CameraConfirmation:
	return camera_confirmation
```

`FleetController.apply_state` calls:

```gdscript
train.apply_camera_state(state)
```

after the per-train loop (once per snapshot), not per train entry.

**Step 3: HUD camera status.**

In `TwinHUD.refresh()`:

```gdscript
var cam_node: CameraConfirmation = current_train.get_camera_confirmation() if is_instance_valid(current_train) and current_train.has_method("get_camera_confirmation") else null
var camera_line := "camera: idle"
if cam_node != null:
	var result := cam_node.get_last_result()
	if result.has("degraded") and bool(result.get("degraded")):
		camera_line = "camera: degraded"
	elif result.get("confirmed", false):
		camera_line = "camera: CONFIRMED %s %.2f" % [str(result.get("species", "wildlife")), float(result.get("confidence", 0.0))]
	elif not result.is_empty():
		camera_line = "camera: %s" % str(result.get("stage", "waiting"))
```

Append `camera_line` to `_status.text`.

**Step 4: Run tests.**

```bash
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_camera_confirmation.gd
/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_wrong_line_hud.gd
```

Expected: PASS.

## Task 17: Web wildlife evidence and camera health

**Files:**
- Modify: `web/src/App.tsx`
- Modify: `web/src/styles.css` if needed

**Step 1: Extend types.**

```tsx
type Hazard = {
  stage: 'NONE' | 'SUSPECTED' | 'CONFIRMED';
  confirmed: boolean;
  confidence: number | null;
  sensorSources: string[];
  camera?: { trainId: string; species: string; confidence: number; at: string } | null;
  sources: string[];
  since?: string;
};

type Block = {
  // existing...
  hazard?: Hazard | null;
};

type CameraHealth = {
  ok: boolean;
  degraded?: boolean;
  ml?: { modelLoaded?: boolean; stub?: boolean; model?: string };
};
```

**Step 2: Fetch health and render evidence.**

```tsx
const [cameraHealth, setCameraHealth] = useState<CameraHealth | null>(null);

async function refresh() {
  // existing state/events
  try { setCameraHealth(await api('/api/wildlife/camera/health')); } catch { setCameraHealth(null); }
}
```

Add a wildlife panel:

```tsx
<section className="panel">
  <div className="panel-head">
    <div><div className="eyebrow">WILDLIFE SAFETY</div><h3>Sensor → Camera → Stop</h3></div>
    <Leaf size={19} />
  </div>
  <div className="wildlife-grid">
    <div><small>Stage</small><b>{blocks.find(b => b.hazard)?.hazard?.stage || 'NONE'}</b></div>
    <div><small>Sources</small><b>{blocks.find(b => b.hazard)?.hazard?.sensorSources?.join(' + ') || '—'}</b></div>
    <div><small>Confidence</small><b>{blocks.find(b => b.hazard)?.hazard?.confidence?.toFixed(2) ?? '—'}</b></div>
    <div><small>Species</small><b>{blocks.find(b => b.hazard)?.hazard?.camera?.species || '—'}</b></div>
    <div><small>Camera</small><b>{cameraHealth?.degraded ? 'DEGRADED' : cameraHealth?.ok ? 'ONLINE' : 'UNKNOWN'}</b></div>
    <div><small>ML</small><b>{cameraHealth?.ml?.modelLoaded ? (cameraHealth.ml.stub ? 'STUB' : 'LOADED') : 'UNAVAILABLE'}</b></div>
  </div>
</section>
```

Update block hazard badges to show `SUSPECTED` vs `CONFIRMED` and use `sensorSources` (map `trackside`→`HUT`, `onboardSensor`→`CAM`).

**Step 3: Build.**

```bash
npm --prefix web run build
```

Expected: PASS.

## Task 19: Two-stage near-animal warning across Godot, backend and ESP32

**Execution order:** Tasks 1–17, Task 19, then Task 18 (final gate). Task 19 is
numbered last but must land before the gate.

**Acceptance conditions**

1. The first qualifying detection sets a service-brake target of 30 km/h. It
   never confirms a RED hazard or commands 0 km/h.
2. Confirmation requires two consecutive qualifying detections within 2 s. On
   confirmation the target becomes 0 km/h and the existing restrictive hazard
   state activates.
3. Simulated and camera/ML detections use the same policy. A single
   high-confidence frame never bypasses confirmation.
4. ESP32 handles `WILDLIFE_NEAR` locally (buzzer, OLED, barrier), but backend
   and Godot enforce the 30 km/h warning whether or not ESP32 is online. ESP32
   telemetry distinguishes `nearAnimal` from `wildlifeDetected`.
5. Clearing a near warning never clears a confirmed hazard. Confirmed hazards
   still require the existing evidence-clear and RESET/re-arm rules.
6. Stopping-distance units are km/h input, m/s² deceleration, seconds latency,
   metres output. The near warning distance is never shorter than the current
   stopping distance for the permitted 0–80 km/h range.

**Files:**
- Modify: `backend/src/config.js`
- Modify: `backend/src/state.js`
- Modify: `backend/src/ingest.js`
- Modify: `backend/src/validate.js`
- Modify: `backend/src/routes/wildlife.js`
- Modify: `godot/src/onboard_braking.gd`
- Modify: `godot/src/simulated_animal_detector.gd`
- Modify: `godot/src/twin_hud.gd`
- Modify: `esp32/src/command_logic.h`
- Modify: `esp32/src/output_logic.h`
- Modify: `esp32/src/actuator.h`
- Modify: `esp32/src/telemetry.h`
- Modify: `esp32/src/railway_controller.ino`
- Modify: `esp32/test/test_logic/test_logic.cpp`
- Modify: `web/src/App.tsx`
- Create: `godot/tests/test_near_animal_warning.gd`
- Modify: `godot/tests/test_onboard_detector.gd`
- Create: `backend/test/near_animal.test.js`
- Modify: `backend/test/camera.test.js`
- Modify: `backend/test/wildlife_observation.test.js`
- Modify: `backend/test/ingest.test.js`

**Step 1: Config and units.**

Add to `config.js`:

```js
nearAnimal: {
  enabled: true,
  serviceSpeedKmh: 30,
  confirmFrames: 2,
  confirmWindowSec: 2,
  nearHoldSec: 3,
  minWarningDistanceM: 40,
  leadFactor: 1.25,
  boxHeightRatio: 0.22,
  boxAreaRatio: 0.05,
  minBoxConfidence: 0.5,
},
```

Validate service speed `0..80`, confirm frames `>= 2`, window `0..10`, hold
`>= 0`, ratios `0..1`, and lead factor `>= 1`.

In `OnboardBraking`:

```gdscript
static func near_distance(speed_kmh: float, camera_range_m: float = 180.0,
		lead_factor: float = 1.25, min_distance_m: float = 40.0) -> float:
	var d_stop := stopping_distance(speed_kmh)
	var wanted := maxf(min_distance_m, d_stop * lead_factor)
	return minf(camera_range_m, wanted)
```

Because `stopping_distance(80) = 161.8 m < 180 m`, the 180 m camera range does
not truncate the warning below a full stop distance. If a future config raises
the maximum speed or lowers the camera range, validation must fail when
`camera_range_m < stopping_distance(maxSpeedKmh)`.

**Step 2: Write backend failing tests.**

`backend/test/near_animal.test.js` must cover:

- one camera frame at confidence 0.9 sets `SUSPECTED`, `targetSpeedKmh <= 30`,
  `confirmed === false`, and publishes exactly one `WILDLIFE_NEAR` command;
- the second frame within 2 s sets `CONFIRMED`, `targetSpeedKmh === 0`, and
  publishes `WILDLIFE_DETECTED`;
- two frames 2.1 s apart do not confirm;
- an observation whose `wildlifeDetected` clears a `SUSPECTED` block clears the
  warning and sends `WILDLIFE_NEAR_CLEAR`;
- clearing near evidence leaves a `CONFIRMED` block `CONFIRMED` until RESET;
- a duplicate `eventId` is ignored and does not resend ESP32 commands;
- with `bus.command` unavailable (ESP32 offline), state still reaches 30 then
  0, and the camera route returns success;
- `WILDLIFE_NEAR` is never sent for a `CONFIRMED` block and
  `WILDLIFE_DETECTED` is never sent for a `SUSPECTED` block;
- `OnboardBraking` formula test for 80 km/h: reaction 13.33 m, braking 123.46 m,
  margin 25 m, total 161.79 m.

**Step 3: Extend observation validation and state.**

`validateWildlifeObservation` accepts optional booleans `nearAnimal` and
`confirmed`. `confirmed === true` is valid only when `source ===
'onboard-camera'` and a `trainId` is present.

`applyWildlifeObservation` returns `stage` and `confirmed`. For
`wildlifeDetected: true`:

```js
const near = obs.nearAnimal === true || hazard.stage === 'SUSPECTED';
const confirmed = obs.confirmed === true;
if (confirmed) {
  hazard.confirmed = true;
  hazard.stage = 'CONFIRMED';
} else if (near && hazard.stage === 'NONE') {
  hazard.stage = 'SUSPECTED';
}
```

Do not let a near observation downgrade a confirmed hazard. A clear observation
sets `hazard.stage = hazard.confirmed ? 'CONFIRMED' : 'NONE'` and never clears
`hazard.confirmed`.

Add `applyCameraNear({ line, blockId, trainId, species, confidence, bbox,
capturedAt })`:

- unknown/mismatched block returns `{ ok: false }`;
- a confirmed block is unchanged and returns `changed: false`;
- a `NONE` block becomes `SUSPECTED`; an existing `SUSPECTED` block stays;
- records camera evidence and sets the zone to `HAZARD`, target
  `nearAnimal.serviceSpeedKmh`;
- sets the matching train's `commandedSpeedKmh`/`targetSpeedKmh` to no more
  than 30 (never raises a lower limit);
- returns `{ ok: true, stage, changed }`.

**Step 4: Camera route streak policy.**

Remove every single-frame confirmation path. The route classifies each
detection:

```js
const near = best && (
  (box[3] - box[1]) >= nearAnimal.boxHeightRatio ||
  ((box[2] - box[0]) * (box[3] - box[1])) >= nearAnimal.boxAreaRatio
);
```

On any qualifying detection, call `applyCameraNear`; if it changed the stage,
publish `WILDLIFE_NEAR` to `railway/commands/esp32` when the block zone is
`config.esp32Zone`. Then update the streak:

```js
streak = previous && now - previous.at <= confirmWindowSec * 1000
  ? previous.count + 1 : 1;
const confirm = streak >= confirmFrames; // no confidence shortcut
```

On confirmation call `applyCameraConfirmation`, write evidence, publish
`WILDLIFE_DETECTED` to ESP32, and return `stage: 'CONFIRMED'`. If the streak
times out, return `stage: 'SUSPECTED'` and keep the 30 km/h warning.

**Step 5: ESP32 commands and local behavior.**

Add `CmdEffect::WILDLIFE_NEAR` and `CmdEffect::WILDLIFE_NEAR_CLEAR`. Accept
`source === 'backend'` for both. Extend `Output` with `WARNING`:

```cpp
inline Output decide_output(bool local_wildlife, bool local_fault,
                            bool comm_ok, bool backend_restrictive,
                            bool backend_near = false) {
  if (local_wildlife || local_fault) return Output::RESTRICTIVE;
  if (!comm_ok) return Output::COMM_LOSS;
  if (backend_restrictive) return Output::RENDER_BACKEND;
  if (backend_near) return Output::WARNING;
  return Output::RENDER_BACKEND;
}
```

`WARNING` closes the barrier, pulses the buzzer, lights the red LED, and shows
`ANIMAL NEAR` on the OLED. `RESTRICTIVE` keeps the existing solid buzzer and
`WILDLIFE` text. Add `backendNearDetected` to the sketch; near clear sets it
false only when `backendWildlifeDetected` is false. `WILDLIFE_CLEARED` and
`RESET` clear both flags.

Add `nearAnimal` to `build_telemetry` and emit it from the sketch. Backend
validation accepts `nearAnimal` as an optional boolean and stores it as
`zones[zone].esp32NearAnimal`; it is informational and never drives safety.

**Step 6: Godot detector and HUD.**

`SimulatedAnimalDetector` no longer immediately stops on `critical`. On the
first consecutive detection it:

```gdscript
_near_active = true
reconciler.set_local_wildlife_limit(30.0)
_publish_observation(true, best, true, false) # near, not confirmed
```

On the second consecutive detection within `detection_persistence` it:

```gdscript
_confirmed = true
reconciler.set_local_wildlife_limit(0.0)
_publish_observation(true, best, true, true) # confirmed
```

On clear it resets both flags, restores the local limit, and publishes
`nearAnimal: false, confirmed: false`. The published payload includes
`distanceM`, `confidence`, `nearAnimal`, and `confirmed`. Near activation also
shows `ANIMAL NEAR — 30 km/h` in `TwinHUD`; confirmation shows the existing
wildlife stop.

`godot/tests/test_near_animal_warning.gd` must assert:

- one detection at 30 m, 36 km/h → local limit 30, not 0;
- a second call → local limit 0;
- `near_distance(80, 180) >= stopping_distance(80)`;
- `stopping_distance(80)` is 161.79 m ±0.05;
- one detection followed by 3 s of no detections clears the warning and does
  not publish a confirmed observation;
- duplicate detector calls do not republish confirmed/near events.

**Step 7: Verdict conditions and full gate.**

Task 19 is complete only when:

```bash
MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test
bash godot/tests/run_tests.sh
pio test -e native --project-dir esp32
```

all pass, and a scripted integration check confirms backend, Godot and ESP32
report the same sequence: `NONE → NEAR/SUSPECTED (30 km/h) → CONFIRMED (0
km/h) → NEAR_CLEAR while CONFIRMED stays latched → CLEAR after RESET`.

## Task 18: Phase 3 integration, acceptance and full gate

**Step 1: Run every suite.**

```bash
bash godot/tests/run_tests.sh
MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test
cd ml && ML_STUB=1 python -m pytest tests -q
pio test -e native --project-dir esp32
pio run -e esp32dev --project-dir esp32
npm --prefix web run build
```

Expected: all green. If the ML tests import torchvision before `ML_STUB` is set, move the import inside `_load()`; the default suite must not download weights.

**Step 2: Live end-to-end chain.**

1. Start broker, backend, ML (`ML_STUB=1 uvicorn app:app --port 8001`), Godot and web.
2. Trigger a trackside or onboard sensor detection in zone1:
   - backend state shows `SUSPECTED`;
   - block aspect YELLOW;
   - train target drops to 30 km/h;
   - Godot `CameraConfirmation` starts uploading frames.
3. In stub mode, the first frame at 0.92 is `SUSPECTED`; the second consecutive
   frame confirms:
   - state shows `CONFIRMED`, `confirmed: true`, species `elephant`, confidence 0.92;
   - block aspect RED;
   - train target 0;
   - evidence file exists at `backend/data/camera-evidence/<eventId>.jpg`;
   - HUD and web show the confirmation.
4. Clear the sensor; the confirmed stop stays latched.
5. `RESET zone1`; state returns to NORMAL, hazard `NONE`, train resumes only after the operator sets speed.

**Step 3: Real-model smoke test when weights are available.**

Run `uvicorn app:app --port 8001` without `ML_STUB`. Verify `/health` reports `modelLoaded: true`; if not, record the degraded result and proceed. Feed one of the elephant captures from `/tmp/opencode` through `/detect` with `curl --data-binary`. Do not commit model weights.

**Step 4: Capture evidence.**

Use 1440×900:
- `capture_animals.gd` for the sensor/camera scene;
- `capture_crossover.gd` for the wrong-line before/mid/after;
- a new `capture_camera_confirm.gd` that sets a `SUSPECTED` hazard, waits for the CameraConfirmation frame, and saves `camera_confirm.png` with the HUD.
- Optionally assemble a GIF with `ffmpeg` under `/tmp/opencode`.

Update `docs/porting/acceptance.md` with:
- stadium layout and opposite-running evidence;
- wrong-line live sequence and hold/reservation evidence;
- sensor → SUSPECTED → camera → CONFIRMED → stop → reset evidence;
- test counts and capture paths;
- explicit note if the real-model smoke test was skipped.

**Step 5: Final review.**

- `git status` must show only intended source/test/doc changes plus the pre-existing untracked spec/plan; no evidence JPEGs or model weights.
- Confirm `.gitignore` covers `backend/data/` and `ml/.cache/`.
- Do not commit unless the user explicitly asks.

---

## Self-Review

**Spec coverage:** Phase 1 covers §5.1–5.5 (geometry, sampler, chainage, station/crossovers, wildlife). Phase 2 covers §6 (eligibility, lifecycle, safety, API, meets). Phase 3 covers §7 (stages, sensor, camera, ML, aspects, reset) and §8–9 (HUD/web). §11 acceptance is split across the three gates and Task 18.

**Review corrections already applied:**
- Train direction fields are initialized once (`travelSign` +1/-1 by line, `operationalSign` +1 for normal movement) so a line change cannot flip the backend movement model.
- The reverse-occupancy test expects B1+B0, matching the mirrored forward-from-offset convention.
- `targetLine` is exported in the train snapshot so Godot can distinguish CROSS_ENTRY (source→destination) from CROSS_EXIT (destination→source).
- Wrong-line timeout uses accumulated `elapsedSec`, not tick count.
- Camera capture copies the existing forward camera transform instead of guessing a local offset.
- RESET clears a latched camera confirmation once no sensor evidence remains.
- The wrong-line test's T3 starts at DOWN-B2 so T1's approach is eligible while T3 remains outside its approach window.

**Known risks to verify during execution:**
- The stadium sampler's `Basis(forward, UP, forward.cross(UP))` must be right-handed; the first test checks positions, and `test_station_island`/`test_river_bridges` check orientation-dependent offsets.
- `LTSTrain._update_train_pose` rotates the basis by π for `travel_sign < 0`; ensure the locomotive model's local +X remains the nose and the forward camera stays ahead.
- `FleetController` must not time-advance route crossings; backend `crossingProgress` is authoritative.
- `occupyBlocks` reverse-direction behavior is intentionally minimal and must not change normal-direction expectations.
- Camera capture uses a dedicated `SubViewport`; never capture the operator's current viewport.
- The backend camera route must be mounted before `express.json` so `express.raw` sees the JPEG body.
- No test may require downloading model weights.



## Completion Record

- **Status:** Complete and closed on 2026-10-23.
- **Commit:** `ef797dc feat: complete stadium camera and near-animal phases`.
- **Acceptance:** `docs/porting/acceptance.md`, Phase 3 section, including the
  live near → camera → confirm → latch → reset chain and evidence frame.
- **Policy reconciliation:** the implemented and tested policy is two
  consecutive qualifying frames within 2 s. All one-frame confirmation
  shortcuts were removed from the spec and this plan.
- **Remaining work:** none in scope. The real-model smoke test remains optional
  and was skipped because no weights were cached; stub ML is verified.
