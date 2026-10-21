# Stage C2 Slice 2B — Double-Track World Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the inner DOWN loop, a two-track corridor (terrain, bridges, level crossing, catenary), an island station in backend block `B2`, and the visible station crossover pair to the Godot twin.

**Architecture:** Add a second `LTSTrack` node (radius 116 m, 4 m inside the outer loop) plus a `TrackRegistry` node that resolves `UP`/`DOWN` lazily. Registry-aware consumers (terrain, scenery, level crossing) keep a single-track fallback so every other scene and test stays green. No trains, fleet rendering, HUD, or signal masts — those are slices 2C–2D.

**Tech Stack:** Godot 4.7 GDScript, procedural meshes, SceneTree test scripts (`godot/tests/test_*.gd`, `Assert` from `test_harness.gd`), `run_tests.sh` headless runner.

**Spec:** `docs/superpowers/specs/2026-10-21-stage-c2-double-track-multitrain-design.md` (§5.1, §6 slice 2B, §7 acceptance 4, §9 approved decisions)

## Global Constraints

- Educational simulation only; never present this as certified signalling or safety equipment.
- UP outer loop: radius `120.0 m`, length `753.9822 m`, centre `(0, -120)` in world XZ. DOWN inner loop: radius `116.0 m`, length `728.8495 m`, same centre, node position `Vector3(0, 0, -4)` so spacing is exactly `4.0 m` centre-to-centre (approved decision 5).
- Backend platform blocks are `UP-B2` = `[301.5929, 452.3893] m` on UP and `DOWN-B2` = `[291.5398, 437.3097] m` on DOWN. Station and crossover visuals must sit inside those ranges. Angle-matched DOWN distance = `up_distance * 728.8495 / 753.9822`.
- Island platform between the two tracks; at 4 m spacing the island must fit between the rails: half-width ≤ `1.15 m` (rail centre at 2.0 m from the midpoint, rail half-width 0.72 m, ≥0.13 m edge clearance).
- Two widened railway bridge decks (approved alternative in §7.4), each spanning both track centre lines.
- One road level-crossing pad covering both tracks, with barrier posts and flashing lamps on both approach sides of the corridor.
- No signal masts, no fleet/train changes, no HUD changes, no backend changes in this slice.
- Every existing test must stay green; new tests are auto-discovered by `godot/tests/run_tests.sh` (`test_*.gd` glob).
- All Godot commands run from the repository root with `GODOT=/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64` (or `bash godot/tests/run_tests.sh`).

---

### Task 1: Inner DOWN track and TrackRegistry

**Files:**
- Create: `godot/src/track_registry.gd`
- Modify: `godot/scenes/lts_full.tscn`
- Modify: `godot/tests/test_parse.gd` (add the new script to `REQUIRED_SCRIPTS`)
- Test: `godot/tests/test_track_registry.gd` (create)

**Interfaces:**
- Consumes: `LTSTrack` (`godot/src/ltstrack.gd`, extends `Rail`), existing `Track` node in `lts_full.tscn`.
- Produces: `TrackRegistry` with `track(line_id: String) -> LTSTrack`, `tracks() -> Array[LTSTrack]`, `line_ids() -> PackedStringArray`, `length_m(line_id: String) -> float`, `first() -> LTSTrack`; scene nodes `InnerTrack` and `TrackRegistry`. Later tasks resolve `DOWN` through `registry.track("DOWN")`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/test_track_registry.gd`:

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

	var registry := scene.get_node_or_null("TrackRegistry") as TrackRegistry
	a.ok(registry != null, "track registry is part of the scene")
	var up: LTSTrack = registry.track("UP") if registry else null
	var down: LTSTrack = registry.track("DOWN") if registry else null
	a.ok(up != null, "UP resolves to the outer track")
	a.ok(down != null, "DOWN resolves to the inner track")
	if down:
		a.ok(absf(down.radius - 116.0) < 0.001, "inner radius is 116 m")
		a.ok(absf(down.length - 728.8495) < 0.01, "inner length is the inner circumference")
		a.ok(absf(down.global_position.z + 4.0) < 0.01, "inner loop starts 4 m inside")
		a.ok(down.get_node_or_null("Rails") != null, "inner track builds rail visuals")
	if registry:
		a.eq(registry.line_ids(), PackedStringArray(["UP", "DOWN"]), "registry reports both lines")
		a.ok(absf(registry.length_m("UP") - 753.9822) < 0.01, "UP length exposed")
		a.ok(registry.first() == scene.get_node("Track"), "first() returns UP")

	for distance in [0.0, 188.4956, 376.9911, 565.4867]:
		var up_pose: Transform3D = up.get_global_transform_at_distance(distance)
		var down_pose: Transform3D = down.get_global_transform_at_distance(distance * 116.0 / 120.0)
		a.ok(absf(up_pose.origin.distance_to(down_pose.origin) - 4.0) < 0.05,
			"4 m spacing at UP %.1f m" % distance)

	scene.queue_free()
	await process_frame
	quit(a.report("test_track_registry"))
```

In `godot/tests/test_parse.gd`, add `"res://src/track_registry.gd",` after the `ltstrack.gd` entry.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -E "test_track_registry|TrackRegistry"`

Expected: FAIL — `TrackRegistry` class does not exist (parse error for the test script), and `scene.get_node_or_null("TrackRegistry")` is null.

- [ ] **Step 3: Write the implementation**

Create `godot/src/track_registry.gd`:

```gdscript
class_name TrackRegistry
extends Node3D

## Lazily resolves the UP (outer) and DOWN (inner) rails for the double-track
## world. Resolution is on demand so node order in the scene does not matter.

@export var up_path: NodePath
@export var down_path: NodePath


func track(line_id: String) -> LTSTrack:
	var path := NodePath()
	if line_id == "UP":
		path = up_path
	elif line_id == "DOWN":
		path = down_path
	return get_node_or_null(path) as LTSTrack


func tracks() -> Array[LTSTrack]:
	var result: Array[LTSTrack] = []
	for id in ["UP", "DOWN"]:
		var found := track(id)
		if found != null:
			result.append(found)
	return result


func line_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for id in ["UP", "DOWN"]:
		if track(id) != null:
			result.append(id)
	return result


func length_m(line_id: String) -> float:
	var found := track(line_id)
	return found.length if found != null else 0.0


func first() -> LTSTrack:
	for id in ["UP", "DOWN"]:
		var found := track(id)
		if found != null:
			return found
	return null
```

Modify `godot/scenes/lts_full.tscn`:
1. Change the header to `load_steps=14`.
2. Add `[ext_resource type="Script" path="res://src/track_registry.gd" id="12"]`.
3. After the `Track` node and before `Train`, add:

```gdscript
[node name="InnerTrack" type="Node3D" parent="."]
script = ExtResource("2")
length = 728.8495
radius = 116.0
max_speed_kmh = 80.0
position = Vector3(0, 0, -4)
```

4. After `TrainReconciler`, add:

```gdscript
[node name="TrackRegistry" type="Node3D" parent="."]
script = ExtResource("12")
up_path = NodePath("../Track")
down_path = NodePath("../InnerTrack")
```

- [ ] **Step 4: Run tests to verify it passes**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -cE "^PASS"`

Expected: `17` (16 existing + `test_track_registry`); no `FAIL` lines.

- [ ] **Step 5: Commit**

```bash
git add godot/src/track_registry.gd godot/scenes/lts_full.tscn godot/tests/test_track_registry.gd godot/tests/test_parse.gd
git commit -m "feat(godot): add inner down track and track registry"
```

---

### Task 2: Two-track terrain corridor

**Files:**
- Modify: `godot/src/terrain_generator.gd`
- Test: `godot/tests/test_corridor_flatten.gd` (create)

**Interfaces:**
- Consumes: `TrackRegistry.tracks()` from Task 1; existing `TerrainGenerator.height_at(x, z) -> float`.
- Produces: `TerrainGenerator` gains `@export var track_paths: Array[NodePath]` and `@export var track_registry_path: NodePath`; `_resolve_tracks()` returns every flattened source. `height_at` behaviour for a single-track scene is unchanged.

Rationale: a 15 m radius around the UP centre line already reaches the DOWN rails, so flatness alone cannot fail before this change. The two-track corridor therefore uses a tighter radius `9.0` sampled from **both** centre lines (a ~22 m corridor), which stops the terrain from mutilating a 30 m-wide swath while still covering both tracks. The tests use a new `is_flattened(x, z)` query to pin the corridor edges: points under either loop and in the mid-corridor are flattened, points 12 m outside the outer rail are not. There is no ballast mesh in this project; the flattened corridor plus sleepers is the visual base.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/test_corridor_flatten.gd`:

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

	var terrain := scene.get_node("WorldWildlife/TerrainGenerator") as TerrainGenerator
	var up := scene.get_node("Track") as LTSTrack
	var down := scene.get_node("InnerTrack") as LTSTrack

	for distance in [0.0, 188.4956, 305.0, 376.9911, 500.0, 660.0]:
		var up_point: Vector3 = up.get_global_transform_at_distance(distance).origin
		a.ok(terrain.height_at(up_point.x, up_point.z) < 0.2,
			"corridor flattened under UP at %.0f m" % distance)
		var down_point: Vector3 = down.get_global_transform_at_distance(distance * 116.0 / 120.0).origin
		a.ok(terrain.height_at(down_point.x, down_point.z) < 0.2,
			"corridor flattened under DOWN at %.0f m" % distance)
		a.ok(terrain.is_flattened(up_point.x, up_point.z), "UP centre line is a flatten source at %.0f m" % distance)
		a.ok(terrain.is_flattened(down_point.x, down_point.z), "DOWN centre line is a flatten source at %.0f m" % distance)
		var mid_point := (up_point + down_point) * 0.5
		a.ok(terrain.is_flattened(mid_point.x, mid_point.z), "mid-corridor is flat at %.0f m" % distance)
		var outer_point: Vector3 = up.get_shifted_global_pos_at_distance(distance, 12.0)
		a.ok(not terrain.is_flattened(outer_point.x, outer_point.z),
			"corridor stops before 12 m outside the outer rail at %.0f m" % distance)

	var river_y := terrain.height_at(0.0, -120.0)
	a.ok(river_y < -2.0, "river channel is still carved")

	scene.queue_free()
	await process_frame
	quit(a.report("test_corridor_flatten"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -A4 "test_corridor_flatten"`

Expected: FAIL — `is_flattened` does not exist, and the 12 m corridor-edge assertion would fail against the old 15 m radius.

- [ ] **Step 3: Write the implementation**

In `godot/src/terrain_generator.gd`:
1. Replace `@export var flatten_radius := 15.0` with `@export var flatten_radius := 9.0`.
2. Add exports after `track_path`:

```gdscript
@export var track_paths: Array[NodePath] = []
@export var track_registry_path: NodePath = NodePath("../../TrackRegistry")
```

3. Replace `_collect_track_samples()` with:

```gdscript
func _collect_track_samples() -> void:
	_track_samples.clear()
	for track in _resolve_tracks():
		var distance := 0.0
		while distance <= track.length:
			_track_samples.append(track.get_global_transform_at_distance(distance).origin)
			distance += 4.0


func _resolve_tracks() -> Array[LTSTrack]:
	var result: Array[LTSTrack] = []
	for path in track_paths:
		var track := get_node_or_null(path) as LTSTrack
		if track != null:
			result.append(track)
	var registry := get_node_or_null(track_registry_path) as TrackRegistry
	if registry != null:
		for track in registry.tracks():
			if not result.has(track):
				result.append(track)
	if result.is_empty():
		var fallback := get_node_or_null(track_path) as LTSTrack
		if fallback == null:
			fallback = get_node_or_null("../../Track") as LTSTrack
		if fallback != null:
			result.append(fallback)
	return result
```

- [ ] **Step 4: Run tests to verify it passes**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -cE "^PASS"`

Expected: `18` (17 + `test_corridor_flatten`); existing `test_river_bridges` and `test_real_assets` still PASS.

- [ ] **Step 5: Commit**

```bash
git add godot/src/terrain_generator.gd godot/tests/test_corridor_flatten.gd
git commit -m "feat(godot): flatten terrain corridor across both tracks"
```

---

### Task 3: Widen both river bridges across the double track

**Files:**
- Modify: `godot/src/railway_bridge.gd`
- Modify: `godot/tests/test_river_bridges.gd`
- Test: same file (extend)

**Interfaces:**
- Consumes: `LTSTrack` poses (`get_global_transform_at_distance`), existing `RailwayBridgeA/B` nodes at fractions `0.25`/`0.75` on `Track`.
- Produces: `RailwayBridge` default `width_m = 12.0`; child nodes named `Deck` (BoxMesh `span_m × 0.42 × width_m`) and `Pier` (4 per bridge). Deck half-width `6.0 m` covers the DOWN centre line at lateral `-4.0 m`; piers at lateral `±5.4 m` clear both centre lines by ≥ `1.25 m`.

- [ ] **Step 1: Write the failing test**

Append to `godot/tests/test_river_bridges.gd` before `scene.queue_free()`:

```gdscript
	var down := scene.get_node("InnerTrack") as LTSTrack
	for bridge in [railway_a, railway_b]:
		if bridge == null:
			continue
		var fraction: float = bridge.get("distance_fraction")
		var up_point: Vector3 = track.get_global_transform_at_distance(track.length * fraction).origin
		var down_point: Vector3 = down.get_global_transform_at_distance(down.length * fraction).origin
		var deck := bridge.get_node_or_null("Deck") as MeshInstance3D
		a.ok(deck != null, "bridge has a named deck")
		if deck:
			var deck_box := _world_aabb(deck)
			a.ok(deck_box.has_point(up_point + Vector3(0.0, -0.5, 0.0)), "deck supports the UP rails")
			a.ok(deck_box.has_point(down_point + Vector3(0.0, -0.5, 0.0)), "deck supports the DOWN rails")
			var deck_mesh := deck.mesh as BoxMesh
			a.ok(deck_mesh != null and deck_mesh.size.z > 10.0, "deck is wide enough for both tracks")
		for pier in bridge.find_children("Pier", "MeshInstance3D", true, false):
			var pier_centre: Vector3 = (pier as MeshInstance3D).global_position
			a.ok(_horizontal_distance(pier_centre, track) > 1.25, "pier clears the UP centre line")
			a.ok(_horizontal_distance(pier_centre, down) > 1.25, "pier clears the DOWN centre line")
```

And add this helper at the bottom of the file:

```gdscript
func _horizontal_distance(point: Vector3, track: LTSTrack) -> float:
	var best := INF
	var distance := 0.0
	while distance <= track.length:
		var sample := track.get_global_transform_at_distance(distance).origin
		best = minf(best, Vector2(point.x - sample.x, point.z - sample.z).length())
		distance += 4.0
	return best


func _world_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var items: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D and not items.has(root):
		items.push_front(root)
	for item in items:
		var mesh_instance := item as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box := mesh_instance.get_aabb()
		for index in 8:
			var point := mesh_instance.global_transform * box.get_endpoint(index)
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result
```

Note: `_world_aabb(deck)` handles the deck root itself (a `MeshInstance3D`, which `find_children` excludes) and computes its world AABB; `deck_box.has_point(up_point + Vector3(0,-0.5,0))` works because the deck's top face is at local `y = -0.29` and the box spans `y ∈ [-0.71, -0.29]` (plus pose origin).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep "test_river_bridges"`

Expected: FAIL — `Bridge has a named deck` (node is anonymous), and the DOWN support assertion fails with the current 6 m deck.

- [ ] **Step 3: Write the implementation**

In `godot/src/railway_bridge.gd`:
1. Change `@export var width_m := 6.0` to `@export var width_m := 12.0`.
2. Name every mesh node and move piers under the widened deck:

```gdscript
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	...
	for side in [-1.0, 1.0]:
		var girder := MeshInstance3D.new()
		girder.name = "Girder"
		...
		for rail_y in [0.42, 0.78]:
			var railing := MeshInstance3D.new()
			railing.name = "Railing"
			...
	for x in [-span_m * 0.3, span_m * 0.3]:
		for z in [-width_m * 0.45, width_m * 0.45]:
			var pier := MeshInstance3D.new()
			pier.name = "Pier"
			...
```

(Only the `name` assignments and `0.32` → `0.45` change; the rest of the mesh construction stays identical.)

- [ ] **Step 4: Run tests to verify it passes**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -cE "^PASS"`

Expected: `18` (no new file; `test_river_bridges` still one PASS). No FAIL lines.

- [ ] **Step 5: Commit**

```bash
git add godot/src/railway_bridge.gd godot/tests/test_river_bridges.gd
git commit -m "feat(godot): widen river bridges across both tracks"
```

---

### Task 4: Level crossing covers both tracks

**Files:**
- Modify: `godot/src/level_crossing.gd`
- Modify: `godot/scenes/world_wildlife.tscn`
- Test: `godot/tests/test_level_crossing_two_track.gd` (create)

**Interfaces:**
- Consumes: `TrackRegistry.tracks()` via `../../TrackRegistry`; existing `LevelCrossing` API (`distance_m`, `set_alarm`, `is_alarm_active`, `is_barrier_down`, `get_crossing_point`).
- Produces: `LevelCrossing` also exposes `get_crossing_points() -> Array[Vector3]` (UP first), builds a named `Pad` centred between the tracks, and two named `BarrierSet0`/`BarrierSet1` structures (one per approach side) whose `BarrierPivot` stands outside both tracks (corridor centre ± `6.0 m`). Existing single-track API and behaviour are unchanged, so `test_wildlife_safety`, `test_esp32_integration`, and `capture_scene.gd` keep working.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/test_level_crossing_two_track.gd`:

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

	var crossing := scene.get_node("WorldWildlife/LevelCrossing") as Node3D
	var up := scene.get_node("Track") as LTSTrack
	var down := scene.get_node("InnerTrack") as LTSTrack
	var points: Array = crossing.call("get_crossing_points")
	a.eq(points.size(), 2, "crossing reports both track points")

	var distance_m: float = crossing.get("distance_m")
	var up_point: Vector3 = up.get_global_transform_at_distance(distance_m).origin
	var down_point: Vector3 = down.get_global_transform_at_distance(distance_m * down.length / up.length).origin
	a.ok(points[0].distance_to(up_point) < 0.5, "first point is the UP crossing")
	a.ok(points[1].distance_to(down_point) < 0.5, "second point is the DOWN crossing")
	a.ok(Vector3(points[0].x, 0.0, points[0].z).distance_to(
		crossing.call("get_crossing_point")) < 0.01, "legacy get_crossing_point still returns UP")

	var pad := crossing.get_node_or_null("Pad") as MeshInstance3D
	a.ok(pad != null, "crossing has a named road pad")
	if pad:
		var pad_box := _world_aabb(pad)
		a.ok(pad_box.has_point(up_point + Vector3(0.0, -0.02, 0.0)), "pad covers the UP track")
		a.ok(pad_box.has_point(down_point + Vector3(0.0, -0.02, 0.0)), "pad covers the DOWN track")

	var pivots := crossing.find_children("BarrierPivot", "Node3D", true, false)
	a.ok(pivots.size() >= 2, "barrier sets frame both approach sides")
	crossing.call("set_alarm", true)
	crossing.call("_process", 1.0)
	a.ok(bool(crossing.call("is_barrier_down")), "alarm lowers the barriers")
	for pivot in pivots:
		a.ok(absf((pivot as Node3D).rotation.z) < 0.05, "every barrier lowers with the alarm")
		var local: Vector3 = crossing.to_local((pivot as Node3D).global_position)
		a.ok(local.z > 3.0 or local.z < -7.0, "barrier stand is clear of both tracks")

	scene.queue_free()
	await process_frame
	quit(a.report("test_level_crossing_two_track"))


func _world_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var items: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D and not items.has(root):
		items.push_front(root)
	for item in items:
		var mesh_instance := item as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box := mesh_instance.get_aabb()
		for index in 8:
			var point := mesh_instance.global_transform * box.get_endpoint(index)
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -A2 "test_level_crossing_two_track"`

Expected: FAIL — `get_crossing_points` does not exist (`Invalid call`), and the pad node is anonymous.

- [ ] **Step 3: Write the implementation**

In `godot/src/level_crossing.gd`:
1. Add exports and state:

```gdscript
@export var track_paths: Array[NodePath] = []
@export var track_registry_path: NodePath = NodePath("../../TrackRegistry")

var _track_poses: Array[Transform3D] = []
```

2. Replace `_place()` with:

```gdscript
func _place() -> void:
	_track_poses.clear()
	var tracks := _resolve_tracks()
	if tracks.is_empty():
		return
	var base_length := tracks[0].length
	for track in tracks:
		_track_poses.append(track.get_global_transform_at_distance(distance_m * track.length / base_length))
	global_transform = _track_poses[0]


func _resolve_tracks() -> Array[LTSTrack]:
	var result: Array[LTSTrack] = []
	for path in track_paths:
		var track := get_node_or_null(path) as LTSTrack
		if track != null:
			result.append(track)
	if result.is_empty():
		var registry := get_node_or_null(track_registry_path) as TrackRegistry
		if registry != null:
			result = registry.tracks()
	if result.is_empty():
		var fallback := get_node_or_null(track_path) as LTSTrack
		if fallback != null:
			result.append(fallback)
	return result
```

3. Replace `_build()` with the pad plus one barrier set per approach side, and add `_pad_local_position()` and `_build_barrier_set()`:

```gdscript
func _build() -> void:
	var asphalt := _material(Color(0.13, 0.14, 0.15), 0.96)
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(10.0, 0.12, 13.0)
	pad.mesh = pad_mesh
	pad.material_override = asphalt
	pad.position = _pad_local_position()
	add_child(pad)
	_build_barrier_set(pad.position.z, -1.0)
	_build_barrier_set(pad.position.z, 1.0)


func _pad_local_position() -> Vector3:
	var local := Vector3(0.0, -0.06, 0.0)
	if _track_poses.size() > 1:
		var centre := Vector3.ZERO
		for pose in _track_poses:
			centre += global_transform.affine_inverse() * pose.origin
		centre /= float(_track_poses.size())
		local.z = centre.z
	return local


func _build_barrier_set(corridor_centre_z: float, side: float) -> void:
	var steel := _material(STEEL, 0.45, 0.5)
	var concrete := _material(CONCRETE, 0.9)
	var red := _material(RED, 0.55)
	var white := _material(WHITE, 0.55)
	var root := Node3D.new()
	root.name = "BarrierSet%d" % (0 if side < 0.0 else 1)
	add_child(root)
	var post_z := corridor_centre_z + side * 4.6
	var pillar_z := corridor_centre_z + side * 6.0

	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.11
	post_mesh.bottom_radius = 0.13
	post_mesh.height = 3.2
	post.mesh = post_mesh
	post.material_override = steel
	post.position = Vector3(0.0, 1.6, post_z)
	root.add_child(post)

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.55, 0.18, 0.55)
	base.mesh = base_mesh
	base.material_override = concrete
	base.position = Vector3(0.0, 0.09, post_z)
	root.add_child(base)

	var housing := MeshInstance3D.new()
	var housing_mesh := BoxMesh.new()
	housing_mesh.size = Vector3(0.72, 0.62, 0.3)
	housing.mesh = housing_mesh
	housing.material_override = steel
	housing.position = Vector3(0.0, 3.35, post_z)
	root.add_child(housing)

	for lamp_x in [-0.2, 0.2]:
		var lamp := MeshInstance3D.new()
		var lamp_mesh := SphereMesh.new()
		lamp_mesh.radius = 0.13
		lamp_mesh.height = 0.26
		lamp.mesh = lamp_mesh
		lamp.material_override = red
		lamp.position = Vector3(lamp_x, 3.35, post_z + (0.18 if side > 0.0 else -0.18))
		lamp.visible = false
		root.add_child(lamp)
		_lamps.append(lamp)

	var sign_root := Node3D.new()
	sign_root.position = Vector3(0.0, 2.65, post_z + (0.08 if side > 0.0 else -0.08))
	root.add_child(sign_root)
	for angle in [-PI / 4.0, PI / 4.0]:
		var board := MeshInstance3D.new()
		var board_mesh := BoxMesh.new()
		board_mesh.size = Vector3(0.9, 0.12, 0.05)
		board.mesh = board_mesh
		board.material_override = red
		board.rotation.z = angle
		sign_root.add_child(board)

	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.55, 0.06, 0.04)
	stripe.mesh = stripe_mesh
	stripe.material_override = white
	stripe.position = Vector3(0.0, -0.7, post_z + (0.05 if side > 0.0 else -0.05))
	root.add_child(stripe)

	var pillar := MeshInstance3D.new()
	var pillar_mesh := BoxMesh.new()
	pillar_mesh.size = Vector3(0.5, 1.2, 0.5)
	pillar.mesh = pillar_mesh
	pillar.material_override = concrete
	pillar.position = Vector3(-4.6, 0.6, pillar_z)
	root.add_child(pillar)

	var pivot := Node3D.new()
	pivot.name = "BarrierPivot"
	pivot.position = Vector3(-4.6, 1.05, pillar_z)
	root.add_child(pivot)
	_pivots.append(pivot)

	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(8.2, 0.2, 0.2)
	arm.mesh = arm_mesh
	arm.material_override = red
	arm.position = Vector3(4.1, 0.0, 0.0)
	pivot.add_child(arm)

	for stripe_x in [1.4, 3.4, 5.4]:
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.8, 0.22, 0.22)
		band.mesh = band_mesh
		band.material_override = white
		band.position = Vector3(float(stripe_x), 0.0, 0.0)
		pivot.add_child(band)

	var tip := MeshInstance3D.new()
	var tip_mesh := BoxMesh.new()
	tip_mesh.size = Vector3(0.7, 0.18, 0.18)
	tip.mesh = tip_mesh
	tip.material_override = white
	tip.position = Vector3(8.2, 0.0, 0.0)
	pivot.add_child(tip)

	pivot.rotation.z = deg_to_rad(82.0)
```

With two tracks the corridor centre is local `z = -2.0`, so posts land at `+2.6`/`-6.6` and pillars at `+4.0`/`-8.0` — every stand is ≥ `1.8 m` from the nearest rail centre, and the pillared side matches the original single-track layout.

4. Add the new API next to `get_crossing_point()`:

```gdscript
func get_crossing_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for pose in _track_poses:
		result.append(pose.origin)
	return result
```

5. In `godot/scenes/world_wildlife.tscn`, update the LevelCrossing node:

```gdscript
[node name="LevelCrossing" type="Node3D" parent="."]
script = ExtResource("12")
track_path = NodePath("../../Track")
track_paths = [NodePath("../../Track"), NodePath("../../InnerTrack")]
distance_m = 260.0
```

- [ ] **Step 4: Run tests to verify it passes**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -cE "^PASS"`

Expected: `19` (18 + `test_level_crossing_two_track`). `test_wildlife_safety` (animal on `get_crossing_point()` triggers STOP and barrier) and `test_esp32_integration` still PASS.

- [ ] **Step 5: Commit**

```bash
git add godot/src/level_crossing.gd godot/scenes/world_wildlife.tscn godot/tests/test_level_crossing_two_track.gd
git commit -m "feat(godot): cover both tracks at the level crossing"
```

---

### Task 5: Island station inside backend block B2

**Files:**
- Modify: `godot/src/scenery_director.gd`
- Test: `godot/tests/test_station_island.gd` (create)

**Interfaces:**
- Consumes: `TrackRegistry`/`InnerTrack` from Task 1; `LTSTrack` poses.
- Produces: `SceneryDirector` gains `@export var registry_path: NodePath = NodePath("../TrackRegistry")`, `@export var inner_track_path: NodePath = NodePath("../InnerTrack")`, `@export var station_module_spacing := 9.6`, `@export var station_modules := 5`; `station_distance` default becomes `322.0` (UP distance of the first module). Nodes named `Platform0`…`Platform4`, each centred between the rails, scaled so lateral half-width ≤ `1.1 m`. `_pose_pair(up_distance)` returns `{"up": Transform3D, "down": Transform3D, "mid": Transform3D}`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/test_station_island.gd`:

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

	var scenery := scene.get_node("Scenery") as SceneryDirector
	var up := scene.get_node("Track") as LTSTrack
	var down := scene.get_node("InnerTrack") as LTSTrack

	for module in 5:
		var d_up: float = scenery.station_distance + module * scenery.station_module_spacing
		var up_pose: Transform3D = up.get_global_transform_at_distance(d_up)
		var down_pose: Transform3D = down.get_global_transform_at_distance(d_up * down.length / up.length)
		var mid := (up_pose.origin + down_pose.origin) * 0.5
		a.ok(d_up > 301.5929 and d_up < 452.3893, "module %d is inside UP-B2" % module)
		var d_down: float = d_up * down.length / up.length
		a.ok(d_down > 291.5398 and d_down < 437.3097, "module %d is inside DOWN-B2" % module)

		var platform := scenery.get_node_or_null("Platform%d" % module) as Node3D
		a.ok(platform != null, "island platform module %d exists" % module)
		if platform == null:
			continue
		var box := _world_aabb(platform)
		var centre := box.get_center()
		a.ok(Vector2(centre.x - mid.x, centre.z - mid.z).length() < 0.8,
			"module %d is centred between the tracks" % module)
		for corner in 8:
			var point := box.get_endpoint(corner)
			var lateral := absf((point - mid).dot(up_pose.basis.z))
			a.ok(lateral <= 1.15, "module %d stays inside the 4 m gap" % module)

	scene.queue_free()
	await process_frame
	quit(a.report("test_station_island"))


func _world_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var items: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D and not items.has(root):
		items.push_front(root)
	for item in items:
		var mesh_instance := item as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box := mesh_instance.get_aabb()
		for index in 8:
			var point := mesh_instance.global_transform * box.get_endpoint(index)
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -A2 "test_station_island"`

Expected: FAIL — `Platform0` is null (modules are anonymous and placed on both sides of the UP track at `station_distance = 70`).

- [ ] **Step 3: Write the implementation**

In `godot/src/scenery_director.gd`:
1. Replace the export block with:

```gdscript
@export var track_path: NodePath = NodePath("../Track")
@export var terrain_path: NodePath = NodePath("../WorldWildlife/TerrainGenerator")
@export var registry_path: NodePath = NodePath("../TrackRegistry")
@export var inner_track_path: NodePath = NodePath("../InnerTrack")
@export var seed := 17
@export var tree_count := 280
@export var station_distance := 322.0
@export var station_module_spacing := 9.6
@export var station_modules := 5
@export var use_lts_models := true
```

2. Add after `_ready()`:

```gdscript
func _inner_track() -> LTSTrack:
	var registry := get_node_or_null(registry_path) as TrackRegistry
	if registry != null:
		var down := registry.track("DOWN")
		if down != null:
			return down
	return get_node_or_null(inner_track_path) as LTSTrack


func _pose_pair(up_distance: float) -> Dictionary:
	var up_pose := _pose(up_distance)
	var down := _inner_track()
	if down == null:
		return {"up": up_pose, "down": null, "mid": up_pose}
	var down_pose := down.get_global_transform_at_distance(clampf(up_distance * down.length / _track.length, 0.0, down.length))
	var mid := up_pose
	mid.origin = (up_pose.origin + down_pose.origin) * 0.5
	return {"up": up_pose, "down": down_pose, "mid": mid}


func _fit_platform(node: Node3D, pose: Transform3D, max_width: float) -> void:
	var box := _world_aabb(node)
	var lateral := 0.0
	for index in 8:
		lateral = maxf(lateral, absf((box.get_endpoint(index) - pose.origin).dot(pose.basis.z)))
	if lateral <= 0.01:
		return
	node.scale *= Vector3.ONE * minf(1.0, (max_width * 0.5) / lateral)
```

3. Replace `_build_station()` with:

```gdscript
func _build_station() -> void:
	var platform_top := 0.55
	for module in station_modules:
		var pair := _pose_pair(station_distance + module * station_module_spacing)
		var mid: Transform3D = pair["mid"]
		var platform := _spawn("platform", mid)
		if platform:
			platform.name = "Platform%d" % module
			_fit_platform(platform, mid, 2.2)
			_align_bottom(platform, mid.origin.y - 1.25)
		if module in [1, 3]:
			var bench_pose := mid
			bench_pose.origin += bench_pose.basis.x * 4.0
			var bench := _spawn("bench", bench_pose)
			if bench:
				_align_bottom(bench, mid.origin.y + platform_top)
			var bin := _spawn("garbage", bench_pose)
			if bin:
				bin.global_position += bench_pose.basis.x * 1.6
				_align_bottom(bin, mid.origin.y + platform_top)

	var house_pose := _pose(station_distance - 8.0, 30.0)
	house_pose.basis = house_pose.basis * Basis(Vector3.UP, -PI / 2.0)
	var house := _spawn("house", house_pose)
	if house:
		_place_on_ground(house)

	var office_pose := _pose(station_distance + 95.0, -34.0)
	office_pose.basis = office_pose.basis * Basis(Vector3.UP, PI / 2.0)
	var office := _spawn("office", office_pose)
	if office:
		_place_on_ground(office)
```

4. Update `_build_canopies()` to the island pose:

```gdscript
func _build_canopies() -> void:
	var metal := _plain_material(Color(0.24, 0.27, 0.30), 0.45, 0.55)
	var roof := _plain_material(Color(0.32, 0.35, 0.38), 0.6, 0.25)
	for module in [1, 2, 3]:
		var pair := _pose_pair(station_distance + module * station_module_spacing + 4.8)
		var root := Node3D.new()
		add_child(root)
		root.global_transform = pair["mid"]
		var slab := MeshInstance3D.new()
		var slab_mesh := BoxMesh.new()
		slab_mesh.size = Vector3(8.4, 0.16, 2.0)
		slab.mesh = slab_mesh
		slab.material_override = roof
		slab.position = Vector3(0.0, 3.85, 0.0)
		root.add_child(slab)
		for post_x in [-3.8, 3.8]:
			for post_z in [-0.8, 0.8]:
				var post := MeshInstance3D.new()
				var post_mesh := BoxMesh.new()
				post_mesh.size = Vector3(0.12, 3.4, 0.12)
				post.mesh = post_mesh
				post.material_override = metal
				post.position = Vector3(post_x, 2.15, post_z)
				root.add_child(post)
```

5. Replace `_build_footbridge()` so the deck spans from beyond the DOWN track to beyond the UP track:

```gdscript
func _build_footbridge() -> void:
	var pair := _pose_pair(station_distance + 24.0)
	var mid: Transform3D = pair["mid"]
	var concrete := _plain_material(Color(0.55, 0.57, 0.58), 0.8)
	var steel := _plain_material(Color(0.30, 0.34, 0.38), 0.4, 0.6)
	var root := Node3D.new()
	add_child(root)
	root.global_transform = mid
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(3.2, 0.35, 13.0)
	deck.mesh = deck_mesh
	deck.material_override = concrete
	deck.position = Vector3(0.0, 7.6, 0.0)
	root.add_child(deck)
	for wall_x in [-1.55, 1.55]:
		var parapet := MeshInstance3D.new()
		var parapet_mesh := BoxMesh.new()
		parapet_mesh.size = Vector3(0.10, 1.05, 13.0)
		parapet.mesh = parapet_mesh
		parapet.material_override = steel
		parapet.position = Vector3(wall_x, 8.3, 0.0)
		root.add_child(parapet)
	for tower_z in [-5.5, 5.5]:
		for tower_x in [-1.1, 1.1]:
			var leg := MeshInstance3D.new()
			var leg_mesh := BoxMesh.new()
			leg_mesh.size = Vector3(0.42, 7.6, 0.42)
			leg.mesh = leg_mesh
			leg.material_override = concrete
			leg.position = Vector3(tower_x, 3.8, tower_z)
			root.add_child(leg)
		var cap := MeshInstance3D.new()
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(2.7, 0.25, 2.2)
		cap.mesh = cap_mesh
		cap.material_override = steel
		cap.position = Vector3(0.0, 7.85, tower_z)
		root.add_child(cap)
```

The deck and parapets span `z ∈ [-6.5, +6.5]` around the island midpoint, clearing the UP rails at `+2` and the DOWN rails at `-2`, and tower legs at `±5.5` stand clear of both rails.

6. Replace `_build_lamps()` to sit on the island midpoint:

```gdscript
func _build_lamps() -> void:
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.16, 0.18, 0.20)
	pole_material.roughness = 0.55
	pole_material.metallic = 0.6
	var lamp_material := StandardMaterial3D.new()
	lamp_material.albedo_color = Color(1.0, 0.86, 0.58)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.82, 0.5)
	lamp_material.emission_energy_multiplier = 2.2
	for module in station_modules:
		var pair := _pose_pair(station_distance + module * station_module_spacing + 4.8)
		var mid: Transform3D = pair["mid"]
		for side in [-1.0, 1.0]:
			var pole_position: Vector3 = mid.origin + mid.basis.z * side * 0.9
			var base_y: float = mid.origin.y + 0.55
			var pole := MeshInstance3D.new()
			var pole_mesh := CylinderMesh.new()
			pole_mesh.top_radius = 0.055
			pole_mesh.bottom_radius = 0.075
			pole_mesh.height = 3.8
			pole.mesh = pole_mesh
			pole.material_override = pole_material
			add_child(pole)
			pole.global_position = Vector3(pole_position.x, base_y + 1.9, pole_position.z)
			var head := MeshInstance3D.new()
			var head_mesh := SphereMesh.new()
			head_mesh.radius = 0.17
			head_mesh.height = 0.34
			head.mesh = head_mesh
			head.material_override = lamp_material
			add_child(head)
			head.global_position = Vector3(pole_position.x, base_y + 3.85, pole_position.z)
			var light := OmniLight3D.new()
			light.position = Vector3(pole_position.x, base_y + 3.75, pole_position.z)
			light.omni_range = 15.0
			light.light_energy = 1.1
			light.light_color = Color(1.0, 0.84, 0.58)
			light.shadow_enabled = false
			add_child(light)
```

7. Replace `_build_station_signs()` so one board stands beside each track, facing it like the original:

```gdscript
func _build_station_signs() -> void:
	for side in [-1.0, 1.0]:
		var pair := _pose_pair(station_distance + 22.0)
		var mid: Transform3D = pair["mid"]
		var root := Node3D.new()
		add_child(root)
		root.global_position = mid.origin + mid.basis.z * side * 0.85 + Vector3(0.0, 3.3, 0.0)
		root.global_basis = Basis.looking_at(mid.basis.z * side, mid.basis.y)
		var board := MeshInstance3D.new()
		var board_mesh := BoxMesh.new()
		board_mesh.size = Vector3(4.2, 1.1, 0.12)
		board.mesh = board_mesh
		board.material_override = _plain_material(Color(0.92, 0.93, 0.9), 0.6)
		root.add_child(board)
		var label := Label3D.new()
		label.text = "WILDTAL"
		label.font_size = 160
		label.pixel_size = 0.0045
		label.modulate = Color(0.08, 0.14, 0.28)
		label.outline_size = 0
		label.position = Vector3(0.0, 0.0, 0.075)
		root.add_child(label)
		for post_x in [-1.8, 1.8]:
			var post := MeshInstance3D.new()
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.1, 3.3, 0.1)
			post.mesh = post_mesh
			post.material_override = _plain_material(Color(0.2, 0.21, 0.22), 0.5, 0.6)
			post.position = Vector3(post_x, -1.65, -0.02)
			root.add_child(post)
```

- [ ] **Step 4: Run tests to verify it passes**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -cE "^PASS"`

Expected: `20` (19 + `test_station_island`). `test_real_assets` (`scenery.get_child_count() > 80`) still PASS.

- [ ] **Step 5: Commit**

```bash
git add godot/src/scenery_director.gd godot/tests/test_station_island.gd
git commit -m "feat(godot): island station inside block B2"
```

---

### Task 6: Visible station crossover pair

**Files:**
- Modify: `godot/src/scenery_director.gd`
- Test: `godot/tests/test_station_crossovers.gd` (create)

**Interfaces:**
- Consumes: `_pose_pair()` from Task 5.
- Produces: `SceneryDirector` gains `@export var crossover_a_up_distance := 312.0` and `@export var crossover_b_up_distance := 434.0`; nodes `CrossoverA`/`CrossoverB` (`Node3D`, metadata `up_distance`/`down_distance`, child `Blades` with ≥ 2 boxes). Each crossover is a lateral track segment centred between the rails: its local Z spans `4.0 m` so its endpoints are exactly on both centre lines.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/test_station_crossovers.gd`:

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

	var scenery := scene.get_node("Scenery") as SceneryDirector
	var up := scene.get_node("Track") as LTSTrack
	var down := scene.get_node("InnerTrack") as LTSTrack

	for entry in [["CrossoverA", scenery.crossover_a_up_distance], ["CrossoverB", scenery.crossover_b_up_distance]]:
		var node_name: String = entry[0]
		var d_up: float = entry[1]
		var d_down: float = d_up * down.length / up.length
		a.ok(d_up > 301.5929 and d_up < 452.3893, "%s is inside UP-B2" % node_name)
		a.ok(d_down > 291.5398 and d_down < 437.3097, "%s is inside DOWN-B2" % node_name)

		var node := scenery.get_node_or_null(node_name) as Node3D
		a.ok(node != null, "%s exists" % node_name)
		if node == null:
			continue
		a.ok(absf(float(node.get_meta("up_distance")) - d_up) < 0.001, "%s records its UP distance" % node_name)
		a.ok(absf(float(node.get_meta("down_distance")) - d_down) < 0.001, "%s records its DOWN distance" % node_name)

		var up_point: Vector3 = up.get_global_transform_at_distance(d_up).origin
		var down_point: Vector3 = down.get_global_transform_at_distance(d_down).origin
		var mid := (up_point + down_point) * 0.5
		a.ok(node.global_position.distance_to(mid) < 0.3, "%s is centred between the rails" % node_name)
		var up_end := node.to_global(Vector3(0.0, 0.0, 2.0))
		var down_end := node.to_global(Vector3(0.0, 0.0, -2.0))
		a.ok(up_end.distance_to(up_point) < 0.3, "%s starts on the UP centre line" % node_name)
		a.ok(down_end.distance_to(down_point) < 0.3, "%s ends on the DOWN centre line" % node_name)

		var blades := node.get_node_or_null("Blades") as Node3D
		a.ok(blades != null, "%s has switch blades" % node_name)
		if blades:
			a.ok(blades.find_children("*", "MeshInstance3D", true, false).size() >= 2,
				"%s has two switch blades" % node_name)

		var platform0 := scenery.get_node_or_null("Platform0") as Node3D
		if platform0:
			a.ok(node.global_position.distance_to(platform0.global_position) > 5.0,
				"%s clears the island platform" % node_name)

	scene.queue_free()
	await process_frame
	quit(a.report("test_station_crossovers"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -A2 "test_station_crossovers"`

Expected: FAIL — `CrossoverA exists` fails (node absent).

- [ ] **Step 3: Write the implementation**

In `godot/src/scenery_director.gd`:

1. Add exports after `station_modules`:

```gdscript
@export var crossover_a_up_distance := 312.0
@export var crossover_b_up_distance := 434.0
```

2. Call `_build_crossovers()` from `_build_details()` and add:

```gdscript
func _build_crossovers() -> void:
	_build_crossover("CrossoverA", crossover_a_up_distance)
	_build_crossover("CrossoverB", crossover_b_up_distance)


func _build_crossover(node_name: String, up_distance: float) -> void:
	var pair := _pose_pair(up_distance)
	if pair["down"] == null:
		return
	var root := Node3D.new()
	root.name = node_name
	add_child(root)
	root.global_transform = pair["mid"]
	var down: LTSTrack = _inner_track()
	root.set_meta("up_distance", up_distance)
	root.set_meta("down_distance", up_distance * down.length / _track.length)

	var ballast := MeshInstance3D.new()
	var ballast_mesh := BoxMesh.new()
	ballast_mesh.size = Vector3(2.2, 0.18, 4.0)
	ballast.mesh = ballast_mesh
	ballast.material_override = _plain_material(Color(0.2, 0.18, 0.16), 0.95)
	ballast.position = Vector3(0.0, -0.14, 0.0)
	root.add_child(ballast)

	var rail_material := _plain_material(Color(0.38, 0.42, 0.44), 0.3, 0.7)
	for side in [-0.7175, 0.7175]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(2.2, 0.16, 0.13)
		rail.mesh = rail_mesh
		rail.material_override = rail_material
		rail.position = Vector3(0.0, 0.02, side)
		root.add_child(rail)

	var sleeper_material := _plain_material(Color(0.22, 0.13, 0.08), 0.9)
	for x in [-0.7, 0.0, 0.7]:
		var sleeper := MeshInstance3D.new()
		var sleeper_mesh := BoxMesh.new()
		sleeper_mesh.size = Vector3(0.18, 0.16, 2.35)
		sleeper.mesh = sleeper_mesh
		sleeper.material_override = sleeper_material
		sleeper.position = Vector3(x, -0.1, 0.0)
		root.add_child(sleeper)

	var blades := Node3D.new()
	blades.name = "Blades"
	blades.position = Vector3(0.0, 0.02, -2.0)
	root.add_child(blades)
	for side in [-0.9, 0.9]:
		var blade := MeshInstance3D.new()
		var blade_mesh := BoxMesh.new()
		blade_mesh.size = Vector3(1.1, 0.12, 0.09)
		blade.mesh = blade_mesh
		blade.material_override = rail_material
		blade.position = Vector3(0.0, 0.0, side * 0.75)
		blade.rotation.y = deg_to_rad(-6.0 if side < 0.0 else 6.0)
		blades.add_child(blade)
```

Note: `pair["mid"].basis` equals the UP pose basis because the matched-angle DOWN pose has the same Y rotation; `basis.z` points outward, so local `+Z` reaches the UP centre line at `+2` and local `-Z` reaches the DOWN centre line at `-2`. The switch blades sit at the DOWN end (`z = -2.0`).

- [ ] **Step 4: Run tests to verify it passes**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -cE "^PASS"`

Expected: `21` (20 + `test_station_crossovers`).

- [ ] **Step 5: Commit**

```bash
git add godot/src/scenery_director.gd godot/tests/test_station_crossovers.gd
git commit -m "feat(godot): visible station crossover pair"
```

---

### Task 7: Catenary over both tracks and tree clearance

**Files:**
- Modify: `godot/src/scenery_director.gd`
- Test: `godot/tests/test_catenary_double.gd` (create)

**Interfaces:**
- Consumes: `_inner_track()` from Task 5; `TrackRegistry` tracks.
- Produces: SceneryDirector exposes `tree_roots() -> Array[Node3D]`; wire nodes `CatenaryWiresUP` and `CatenaryWiresDOWN` (each a `MeshInstance3D` with a line mesh at heights `5.55`/`6.45` above its track). Tree placement minimum offset rises from `11.0` to `12.0 m` so no tree is within `5 m` of either centre line.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/test_catenary_double.gd`:

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

	var scenery := scene.get_node("Scenery") as SceneryDirector
	var down := scene.get_node("InnerTrack") as LTSTrack
	var up := scene.get_node("Track") as LTSTrack

	for node_name in ["CatenaryWiresUP", "CatenaryWiresDOWN"]:
		var wires := scenery.get_node_or_null(node_name) as MeshInstance3D
		a.ok(wires != null, "%s exists" % node_name)
		if wires:
			a.ok(wires.mesh != null and wires.mesh.get_surface_count() >= 1, "%s has wire geometry" % node_name)

	var down_wires := scenery.get_node_or_null("CatenaryWiresDOWN") as MeshInstance3D
	if down_wires:
		for distance in [60.0, 300.0, 600.0]:
			var target: Vector3 = down.get_global_transform_at_distance(distance).origin + Vector3(0.0, 5.55, 0.0)
			a.ok(_mesh_has_vertex_near(down_wires.mesh, target, 0.35),
				"DOWN catenary passes above the track at %.0f m" % distance)

	for tree in scenery.tree_roots():
		var position: Vector3 = tree.global_position
		var direction := 0.0
		while direction <= up.length:
			var up_sample := up.get_global_transform_at_distance(direction).origin
			a.ok(Vector2(position.x - up_sample.x, position.z - up_sample.z).length() > 5.0,
				"no tree within 5 m of the UP centre line")
			var down_sample := down.get_global_transform_at_distance(direction * down.length / up.length).origin
			a.ok(Vector2(position.x - down_sample.x, position.z - down_sample.z).length() > 5.0,
				"no tree within 5 m of the DOWN centre line")
			direction += 8.0

	scene.queue_free()
	await process_frame
	quit(a.report("test_catenary_double"))


func _mesh_has_vertex_near(mesh: Mesh, target: Vector3, tolerance: float) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		if vertex.distance_to(target) < tolerance:
			return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -A2 "test_catenary_double"`

Expected: FAIL — `CatenaryWiresUP exists` and `CatenaryWiresDOWN exists` fail (`CatenaryWires` is the only wire node today), and `tree_roots()` does not exist.

- [ ] **Step 3: Write the implementation**

In `godot/src/scenery_director.gd`:
1. Replace `_build_wires()` with a per-track builder and keep the name `CatenaryWiresUP` for the outer loop:

```gdscript
func _build_wires() -> void:
	_build_track_wires(_track, "CatenaryWiresUP")
	var down := _inner_track()
	if down != null:
		_build_track_wires(down, "CatenaryWiresDOWN")


func _build_track_wires(track: LTSTrack, node_name: String) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.17, 0.18)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var distance := 0.0
	while distance < track.length - 6.0:
		var a := track.get_global_transform_at_distance(distance).origin
		var b := track.get_global_transform_at_distance(distance + 6.0).origin
		for height in [5.55, 6.45]:
			mesh.surface_add_vertex(a + Vector3.UP * height)
			mesh.surface_add_vertex(b + Vector3.UP * height)
		if int(distance / 6.0) % 2 == 0:
			mesh.surface_add_vertex(a + Vector3.UP * 5.55)
			mesh.surface_add_vertex(a + Vector3.UP * 6.45)
		distance += 6.0
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	add_child(instance)
```

2. In `_scatter_trees()`, change `var offset := _rng.randf_range(11.0, 62.0)` to `var offset := _rng.randf_range(12.0, 62.0)`.

3. Add the accessor:

```gdscript
func tree_roots() -> Array[Node3D]:
	return _tree_roots
```

- [ ] **Step 4: Run tests to verify it passes**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -cE "^PASS"`

Expected: `22` (21 + `test_catenary_double`).

- [ ] **Step 5: Commit**

```bash
git add godot/src/scenery_director.gd godot/tests/test_catenary_double.gd
git commit -m "feat(godot): catenary over both tracks and tree clearance"
```

---

### Task 8: Slice regression, visual capture, and docs

**Files:**
- Create: `godot/tests/capture_double_track.gd`
- Modify: `docs/porting/acceptance.md`
- Test: full suites

**Interfaces:**
- Consumes: everything from Tasks 1–7; existing `capture_scene.gd` conventions (`RenderingServer.force_draw`, `root.get_texture().get_image().save_png`).
- Produces: `/tmp/opencode/double_track_overview.png`; an acceptance-doc section "Stage 2B double-track world verification (2026-10-22)".

- [ ] **Step 1: Create the capture script**

Create `godot/tests/capture_double_track.gd`:

```gdscript
extends SceneTree

## Run: xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 \
##        --path godot --resolution 1280x720 --rendering-method gl_compatibility \
##        --script res://tests/capture_double_track.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	for frame in 12:
		await process_frame
	var camera := Camera3D.new()
	camera.fov = 58.0
	camera.far = 2000.0
	scene.add_child(camera)
	camera.global_position = Vector3(0.0, 175.0, 95.0)
	camera.look_at(Vector3(0.0, 0.0, -120.0), Vector3.UP)
	camera.make_current()
	for frame in 3:
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/opencode/double_track_overview.png")
	quit()
```

- [ ] **Step 2: Run the full Godot suite**

Run: `bash godot/tests/run_tests.sh 2>&1 | grep -cE "^PASS"`

Expected: `22`; then `bash godot/tests/run_tests.sh 2>&1 | grep -c FAIL` → `0`.

- [ ] **Step 3: Run the backend and ESP32 regression**

Run: `MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test 2>&1 | grep -E "^ℹ (tests|pass|fail)"` with the disposable broker (`docker run -d --rm --name rdt-test-mqtt -p 127.0.0.1:1884:1883 -v "$PWD/mosquitto:/mosquitto/config:ro" eclipse-mosquitto:2`).

Expected: `tests 84`, `pass 84`, `fail 0`.

Then run: `cd esp32 && pio test -e native 2>&1 | tail -2 && pio run -e esp32dev 2>&1 | tail -2`

Expected: `14 test cases: 14 succeeded` and `esp32dev SUCCESS`.

- [ ] **Step 4: Capture the double-track overview and inspect it**

Run: `xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --path godot --resolution 1280x720 --rendering-method gl_compatibility --script res://tests/capture_double_track.gd`

Expected: `/tmp/opencode/double_track_overview.png` exists and is non-zero. Read the PNG and confirm both concentric loops are continuous, the island station sits between them at the top of the ring, the crossover segments are visible near the station, both bridges cross the river, and no terrain gap is visible under either rail.

- [ ] **Step 5: Update the acceptance doc**

Add to `docs/porting/acceptance.md`, after the Stage 2A section:

```markdown
## Stage 2B double-track world verification (2026-10-22)

The twin renders two concentric loops (UP radius 120 m, DOWN radius 116 m,
4.0 m spacing), an island station inside backend block `B2`, the visible
station crossover pair, widened river bridges, and a two-track level crossing.

| Item | Evidence |
|---|---|
| Inner loop + registry | `test_track_registry.gd`: DOWN radius/length/offset, 4 m spacing at four angles, `TrackRegistry` maps both lines |
| Corridor | `test_corridor_flatten.gd`: both centre lines and the mid-corridor are flatten sources, the corridor ends 12 m outside the outer rail; river still carved |
| River bridges | `test_river_bridges.gd`: one 12 m deck per river crossing covers both centre lines; piers clear both rails |
| Level crossing | `test_level_crossing_two_track.gd`: two crossing points, pad covers both tracks, both barrier sets (2 pivots) stand clear of both tracks and lower together |
| Island station | `test_station_island.gd`: five modules centred between the rails inside `UP-B2`/`DOWN-B2`, half-width ≤ 1.15 m |
| Crossovers | `test_station_crossovers.gd`: `CrossoverA` (UP 312 m) and `CrossoverB` (UP 434 m) end on both centre lines, switch blades present |
| Catenary + trees | `test_catenary_double.gd`: wire runs above both lines; no tree within 5 m of either centre line |
| Regression | Godot 22/22, backend 84/84, ESP32 native 14/14, `pio run -e esp32dev` PASS |
| Capture | `/tmp/opencode/double_track_overview.png` (double-track overview) |

Signal masts, remote fleet rendering, and meet/pass remain in slices 2C–2D.
```

- [ ] **Step 6: Commit**

```bash
git add godot/tests/capture_double_track.gd docs/porting/acceptance.md
git commit -m "docs(c2): record stage 2B double-track world evidence"
```

---

## Stage 2B Exit Gate

- Both concentric loops render with no unsupported track or terrain gaps
  (`test_track_registry`, `test_corridor_flatten`, capture).
- Two widened bridge decks carry both centre lines over the river
  (`test_river_bridges`).
- One level-crossing pad and barrier set cover both tracks
  (`test_level_crossing_two_track`).
- Island station and crossover pair sit inside backend blocks `UP-B2`/`DOWN-B2`
  (`test_station_island`, `test_station_crossovers`).
- All pre-existing Godot tests stay green; backend and ESP32 suites unchanged.
- Do not start 2C until every exit-gate item has executed evidence.
```
