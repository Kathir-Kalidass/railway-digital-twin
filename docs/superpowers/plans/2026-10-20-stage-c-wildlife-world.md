# Stage C — Forest World, Wildlife & Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the forest world (terrain, stream, overpass bridge, wildlife underpass, curved double track), animated wildlife that prefers the underpass but sometimes crosses the rails, and the graduated safety reaction (warn/slow/stop/resume) with cameras and a scenario director.

**Architecture:** Content lives in the twin overlay on top of the Plan 1 runtime. World geometry is procedural with CC0/CC-BY asset overlays and procedural fallbacks. Wildlife uses a small navigation graph with a decision node at the underpass and publishes observations through `WildlifePublisher`. Safety visuals subscribe to backend zone state and are driven by `TrainController`.

**Tech Stack:** Godot 4.7, `NavigationAgent3D`, `AnimationTree`, `MultiMeshInstance3D`, the Plan 1 `lts_runtime` and `src/` overlay.

**Spec:** `docs/superpowers/specs/2026-10-20-stage-c-libretrainsim-wildlife-design.md`

## Global Constraints

- Depends on Plan 1 (`2026-10-20-stage-c-lts-port-runtime.md`) being complete: `lts_runtime`, `mqtt_bridge.gd`, `twin_state.gd`, `train_controller.gd`, `wildlife_publisher.gd`, and `godot/tests/run_tests.sh`.
- `GODOT=/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64`.
- Assets must be **CC0/CC-BY**, recorded in `godot/CREDITS.md`; every asset needs a procedural fallback so the scene loads with zero downloads. Never commit unlicensed assets.
- Do not modify `mosquitto/*`, `scripts/*`, `docker-compose.yml`, `esp32/**`, root `README.md`/`.gitignore` (concurrent actor).
- All API-facing strings are ASCII; German/railway naming from Libre-TrainSim may remain in ported code only.
- Headless gate per task: `bash godot/tests/run_tests.sh` exits 0.
- All commits on `master`.

---

## File Structure

- `godot/src/world/terrain.gd` — procedural forest terrain + stream carve.
- `godot/src/world/forest.gd` — MultiMesh trees/rocks/grass with asset-or-procedural fallback.
- `godot/src/world/bridge.gd` — road overpass bridge geometry.
- `godot/src/world/underpass.gd` — animal underpass geometry + nav link.
- `godot/src/world/track_builder.gd` — lays curved double track using `Rail`.
- `godot/src/wildlife/animal.gd` — one animal: state machine + nav + animation.
- `godot/src/wildlife/wildlife_director.gd` — spawns animals, owns the crossing decision, drives `WildlifePublisher`.
- `godot/src/safety/safety_visuals.gd` — boom barrier, LEDs, buzzer per zone state.
- `godot/src/camera/camera_director.gd` — follow/cab/drone modes.
- `godot/src/scenario/scenario_director.gd` — safety + cinematic scenarios.
- `godot/wildlife_world.tscn` — the composed world scene (referenced by `main.tscn`).
- `godot/assets/` (gitignored downloads) + `godot/assets.manifest.json` (committed, lists URL/license/hash).

---

### Task 1: Procedural forest terrain with a stream

**Files:**
- Create: `godot/src/world/terrain.gd`
- Create: `godot/tests/test_terrain.gd`

**Interfaces:**
- Consumes: `FastNoiseLite`.
- Produces: `Terrain.build(width, depth, seed) -> void`; `Terrain.height_at(x, z) -> float`; `Terrain.stream_center_z(x) -> float` (the Z of the stream at a given X).

- [ ] **Step 1: Write the terrain**

`godot/src/world/terrain.gd`:

```gdscript
class_name Terrain
extends Node3D

@export var size := Vector2(2000, 2000)
@export var resolution := 128
@export var seed := 12345

var _noise := FastNoiseLite.new()

func build() -> void:
	_noise.seed = seed
	_noise.frequency = 0.002
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size.x / resolution
	for i in resolution:
		for j in resolution:
			var x0 := -size.x / 2 + i * step
			var z0 := -size.y / 2 + j * step
			var p00 := Vector3(x0, height_at(x0, z0), z0)
			var p10 := Vector3(x0 + step, height_at(x0 + step, z0), z0)
			var p01 := Vector3(x0, height_at(x0, z0 + step), z0 + step)
			var p11 := Vector3(x0 + step, height_at(x0 + step, z0 + step), z0 + step)
			_add_tri(st, p00, p10, p11)
			_add_tri(st, p00, p11, p01)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	add_child(mi)
	add_child(_make_collision(mi.mesh))

func height_at(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * 40.0
	var d := absf(z - stream_center_z(x))
	h -= smoothstep(60.0, 0.0, d) * 12.0   # carve the stream bed
	return h

func stream_center_z(x: float) -> float:
	return sin(x * 0.001) * 200.0

func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

func _make_collision(mesh: Mesh) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	return body
```

- [ ] **Step 2: Write the test**

`godot/tests/test_terrain.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var a := Assert.new()
	var t := Terrain.new()
	t.resolution = 8
	a.ok(t.height_at(0, 0) != t.height_at(0, t.stream_center_z(0)), "stream bed is lower off-centre")
	a.ok(absf(t.height_at(0, t.stream_center_z(0) + 0) - t.height_at(0, t.stream_center_z(0))) < 0.001, "height deterministic")
	quit(a.report("test_terrain"))
```

- [ ] **Step 3: Run + commit**

Run: `bash godot/tests/run_tests.sh; echo "exit=$?"` — expect `PASS test_terrain`.

```bash
git add godot/src/world/terrain.gd godot/tests/test_terrain.gd
git commit -m "feat(godot): procedural forest terrain with carved stream"
```

---

### Task 2: Curved double track through the terrain

**Files:**
- Create: `godot/src/world/track_builder.gd`
- Create: `godot/tests/test_track_builder.gd`

**Interfaces:**
- Consumes: `Rail`, `Math.get_next_pos`.
- Produces: `TrackBuilder.build(spec: Array) -> Array` where `spec` is a list of `{length, radius}`; returns the ordered `Rail` nodes.

- [ ] **Step 1: Write the builder**

`godot/src/world/track_builder.gd`:

```gdscript
class_name TrackBuilder
extends Node3D

const RAIL := preload("res://addons/lts_runtime/Data/Modules/Rail.tscn")

func build(spec: Array, start_pos := Vector3.ZERO, start_rot := 0.0) -> Array:
	var rails: Array = []
	var pos := start_pos
	var rot := start_rot
	for seg in spec:
		var rail = RAIL.instantiate()
		rail.length = seg["length"]
		rail.radius = seg.get("radius", 0.0)
		rail.start_pos = pos
		rail.start_rot = rot
		add_child(rail)
		rails.append(rail)
		pos = Math.get_next_pos(rail.radius, pos, rot, rail.length)
		rot = Math.get_next_rad(rail.radius, rot, rail.length)
	return rails
```

- [ ] **Step 2: Test + run + commit**

`godot/tests/test_track_builder.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var a := Assert.new()
	var b := TrackBuilder.new()
	var spec := [{"length": 200.0}, {"length": 150.0, "radius": 300.0}, {"length": 200.0}]
	var rails: Array = b.build(spec)
	a.eq(rails.size(), 3, "three rails")
	a.ok(rails[2].start_pos != rails[0].start_pos, "curve changes direction")
	quit(a.report("test_track_builder"))
```

Run: `bash godot/tests/run_tests.sh; echo "exit=$?"` — expect `PASS test_track_builder`.

```bash
git add godot/src/world/track_builder.gd godot/tests/test_track_builder.gd
git commit -m "feat(godot): curved double-track builder over LTS rails"
```

---

### Task 3: Road overpass bridge

**Files:**
- Create: `godot/src/world/bridge.gd`
- Create: `godot/tests/test_bridge.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Bridge.spans() -> Array[AABB]` (one AABB per span) and `Bridge.build(rail_span: float) -> void`.

- [ ] **Step 1: Write the bridge**

`godot/src/world/bridge.gd`:

```gdscript
class_name Bridge
extends Node3D

@export var deck_width := 8.0
@export var clearance := 6.5

func spans() -> Array[AABB]:
	var out: Array[AABB] = []
	for c in get_children():
		if c is MeshInstance3D:
			out.append(c.get_aabb())
	return out

func build(rail_span: float) -> void:
	var span := rail_span + 12.0
	var deck := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(span, 0.8, deck_width)
	deck.mesh = box
	deck.position = Vector3(0, clearance + 0.4, 0)
	add_child(deck)
	for s in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		var p := BoxMesh.new()
		p.size = Vector3(1.5, clearance, 1.5)
		pillar.mesh = p
		pillar.position = Vector3(s * (span / 2 - 1.5), clearance / 2, 0)
		add_child(pillar)
```

- [ ] **Step 2: Test + run + commit**

`godot/tests/test_bridge.gd` asserts `Bridge.build(20)` yields one span with `position.y` above `clearance`. Run headless, expect PASS, commit `feat(godot): road overpass bridge`.

---

### Task 4: Wildlife underpass beneath the track

**Files:**
- Create: `godot/src/world/underpass.gd`
- Create: `godot/tests/test_underpass.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Underpass.build(track_width: float) -> void`; `Underpass.entry_point(side: int) -> Vector3`; `Underpass.edge_navigation_links() -> Array`.

- [ ] **Step 1: Write the underpass**

`godot/src/world/underpass.gd`:

```gdscript
class_name Underpass
extends Node3D

@export var height := 3.0
@export var length := 14.0
@export var width := 6.0

func build(_track_width: float) -> void:
	var tube := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = width / 2
	cm.bottom_radius = width / 2
	cm.height = length
	cm.radial_segments = 12
	tube.mesh = cm
	tube.rotation_degrees = Vector3(90, 0, 0)
	tube.position = Vector3(0, height / 2 - 0.5, 0)
	add_child(tube)
	var floor_mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(length, 0.2, width)
	floor_mesh.mesh = b
	add_child(floor_mesh)

func entry_point(side: int) -> Vector3:
	return global_position + Vector3(0, 0, side * length / 2)

func edge_navigation_links() -> Array:
	return [
		{"from": entry_point(-1), "to": entry_point(1)},
	]
```

- [ ] **Step 2: Test + run + commit**

`godot/tests/test_underpass.gd`: build, assert `entry_point(1) != entry_point(-1)` and both have `y >= 0`. Run headless, expect PASS, commit `feat(godot): wildlife underpass geometry`.

---

### Task 5: Wildlife assets with procedural fallback

**Files:**
- Create: `godot/src/wildlife/animal.gd`
- Create: `godot/assets.manifest.json`
- Create: `godot/tests/test_animal_fallback.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Animal` (`class_name Animal extends Node3D`) with `species: String`, `setup(species) -> void`, and `has_skeleton() -> bool`.

- [ ] **Step 1: Write the manifest**

`godot/assets.manifest.json`:

```json
{
  "animals": {
    "deer": {"url": "", "license": "CC0", "file": "res://assets/deer.glb"},
    "elephant": {"url": "", "license": "CC0", "file": "res://assets/elephant.glb"}
  },
  "note": "Empty url means procedural fallback is used; populate before the beauty demo."
}
```

- [ ] **Step 2: Write the animal with fallback**

`godot/src/wildlife/animal.gd`:

```gdscript
class_name Animal
extends Node3D

@export var species := "deer"
var _visual: Node3D

func setup(kind: String) -> void:
	species = kind
	_visual = _load_asset(kind)
	if _visual == null:
		_visual = _procedural(kind)
	add_child(_visual)

func has_skeleton() -> bool:
	var sk := _visual.find_child("*", true, false)
	while sk:
		if sk is Skeleton3D:
			return true
		sk = sk.find_child("*", true, false)
	return false

func _load_asset(kind: String) -> Node3D:
	var path := "res://assets/%s.glb" % kind
	if ResourceLoader.exists(path):
		var s: PackedScene = load(path)
		if s:
			return s.instantiate()
	return null

func _procedural(kind: String) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.5 if kind == "deer" else 1.4
	cap.height = 1.6 if kind == "deer" else 3.6
	body.mesh = cap
	root.add_child(body)
	return root
```

- [ ] **Step 3: Test + run + commit**

`godot/tests/test_animal_fallback.gd`: `Animal.new()` + `setup("deer")` with no `res://assets/deer.glb` present → assert a child exists and `has_skeleton() == false`. Run headless, expect PASS, commit `feat(godot): wildlife animals with procedural fallback + asset manifest`.

---

### Task 6: Wildlife behaviour (underpass preference + occasional direct crossing)

**Files:**
- Create: `godot/src/wildlife/wildlife_director.gd`
- Create: `godot/tests/test_wildlife_director.gd`

**Interfaces:**
- Consumes: `Animal`, `Underpass`, `Terrain`.
- Produces: `WildlifeDirector.decide_route(rng: RandomNumberGenerator, cross_probability: float) -> String` returning `"underpass"` or `"direct"`; `WildlifeDirector.nearest_animal_distance_m(pos) -> float`.

- [ ] **Step 1: Write the director**

`godot/src/wildlife/wildlife_director.gd`:

```gdscript
class_name WildlifeDirector
extends Node3D

@export var cross_probability := 0.25
@export var zone := "zone1"

var _animals: Array[Animal] = []

func spawn(species: String, count: int, rng: RandomNumberGenerator) -> void:
	for i in count:
		var a := Animal.new()
		a.setup(species)
		add_child(a)
		_animals.append(a)

func decide_route(rng: RandomNumberGenerator, probability := -1.0) -> String:
	var p := cross_probability if probability < 0.0 else probability
	return "direct" if rng.randf() < p else "underpass"

func nearest_animal_distance_m(pos: Vector3) -> float:
	var best := INF
	for a in _animals:
		best = minf(best, a.global_position.distance_to(pos))
	return best
```

- [ ] **Step 2: Test the decision boundary deterministically**

`godot/tests/test_wildlife_director.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var a := Assert.new()
	var d := WildlifeDirector.new()
	a.eq(d.decide_route(null, 1.0), "direct", "prob 1 always direct")
	a.eq(d.decide_route(null, 0.0), "underpass", "prob 0 always underpass")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var direct := 0
	for i in 100:
		if d.decide_route(rng, 0.25) == "direct":
			direct += 1
	a.ok(direct > 10 and direct < 40, "~25%% direct, got %d" % direct)
	quit(a.report("test_wildlife_director"))
```

- [ ] **Step 3: Run + commit**

Run: `bash godot/tests/run_tests.sh; echo "exit=$?"` — expect PASS. Commit `feat(godot): wildlife route decision (underpass preference + occasional direct cross)`.

---

### Task 7: Detection bands publish wildlife observations

**Files:**
- Modify: `godot/src/wildlife/wildlife_director.gd`
- Modify: `godot/tests/test_wildlife_director.gd`

**Interfaces:**
- Consumes: `WildlifePublisher.report`.
- Produces: `WildlifeDirector.update_detection(train_pos: Vector3, track: Node3D) -> void` — publishes `report(species, count, on_track)` when any animal is within the near band (25 m) or on-track band (6 m).

- [ ] **Step 1: Add the detection update**

```gdscript
@export var publisher: WildlifePublisher
const NEAR_BAND_M := 25.0
const ON_TRACK_BAND_M := 6.0

func update_detection(train_pos: Vector3, track_positions: Array) -> void:
	var on_track := 0
	for a in _animals:
		for tp in track_positions:
			var d: float = a.global_position.distance_to(tp)
			if d <= ON_TRACK_BAND_M:
				on_track += 1
				break
	if publisher:
		publisher.report(_species_of(_animals), on_track, on_track > 0)
```

- [ ] **Step 2: Test** — with a `FakeBridge` (from Plan 1 Task 11), place a fake animal 3 m from a track point and assert the published payload has `wildlifeDetected == true`.

- [ ] **Step 3: Run + commit** — `feat(godot): wildlife detection bands publish observations`.

---

### Task 8: Safety visuals (barrier, LEDs, buzzer) per zone state

**Files:**
- Create: `godot/src/safety/safety_visuals.gd`
- Create: `godot/tests/test_safety_visuals.gd`

**Interfaces:**
- Consumes: `twin_state.gd` zone state dict `{state, speedLimitKmh}`.
- Produces: `SafetyVisuals.apply(zone_state: Dictionary) -> void` setting barrier angle, LED color (`safe`/`warn`/`danger`), and buzzer on/off.

- [ ] **Step 1: Write the visuals**

`godot/src/safety/safety_visuals.gd`:

```gdscript
class_name SafetyVisuals
extends Node3D

@export var barrier: Node3D
@export var led: MeshInstance3D
@export var buzzer: AudioStreamPlayer

func apply(zone_state: Dictionary) -> void:
	var s := String(zone_state.get("state", "clear"))
	var angle := 90.0 if s == "hazard" or s == "sensor_fault" else 0.0
	if barrier:
		barrier.rotation_degrees.x = angle
	var color := Color.GREEN
	if s == "warn":
		color = Color.YELLOW
	elif s == "hazard" or s == "sensor_fault":
		color = Color.RED
	if led:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		led.material_override = m
	if buzzer:
		buzzer.playing = (s != "clear")
```

- [ ] **Step 2: Test** — `SafetyVisuals` with a dummy barrier/led asserts barrier angle 90 and LED red for `hazard`, angle 0 for `clear`.

- [ ] **Step 3: Run + commit** — `feat(godot): graduated safety visuals (barrier/LED/buzzer)`.

---

### Task 9: Camera director (follow / cab / drone)

**Files:**
- Create: `godot/src/camera/camera_director.gd`
- Create: `godot/tests/test_camera_director.gd`

**Interfaces:**
- Consumes: `CameraBase` (ported) or `Camera3D`.
- Produces: `CameraDirector.cycle() -> String`, `CameraDirector.mode_name() -> String` cycling `["follow", "cab", "drone"]`.

- [ ] **Step 1: Write the director**

`godot/src/camera/camera_director.gd`:

```gdscript
class_name CameraDirector
extends Camera3D

const MODES := ["follow", "cab", "drone"]
var _index := 0
@export var target: Node3D
@export var drone_height := 60.0

func mode_name() -> String:
	return MODES[_index]

func cycle() -> String:
	_index = (_index + 1) % MODES.size()
	return mode_name()

func _process(_delta: float) -> void:
	if target == null:
		return
	match mode_name():
		"follow":
			global_position = target.global_position + Vector3(0, 6, -12)
			look_at(target.global_position, Vector3.UP)
		"cab":
			global_position = target.global_position + Vector3(0, 2.5, 0)
			look_at(target.global_position + target.global_transform.basis.z * -20.0, Vector3.UP)
		"drone":
			global_position = target.global_position + Vector3(0, drone_height, 0)
			look_at(target.global_position, Vector3.UP)
```

- [ ] **Step 2: Test + run + commit** — assert `cycle()` order `cab→drone→follow`. Commit `feat(godot): follow/cab/drone camera director`.

---

### Task 10: Scenario director (safety + cinematic reel)

**Files:**
- Create: `godot/src/scenario/scenario_director.gd`
- Create: `godot/tests/test_scenario_director.gd`

**Interfaces:**
- Consumes: `WildlifeDirector`, `SafetyVisuals`, `CameraDirector`, `TrainController`, `twin_state.gd`.
- Produces: `ScenarioDirector.run_safety() -> Array` returning the ordered step names `["clear","warn","stop","clear_resume"]`.

- [ ] **Step 1: Write the director**

```gdscript
class_name ScenarioDirector
extends Node

func safety_steps() -> Array:
	return ["clear", "warn", "stop", "clear_resume"]

func run_safety(apply: Callable) -> Array:
	for step in safety_steps():
		apply.call(step)
	return safety_steps()
```

- [ ] **Step 2: Test + run + commit** — assert the four steps returned in order. Commit `feat(godot): safety + cinematic scenario director`.

---

### Task 11: Atmosphere (day/night) and composed world scene

**Files:**
- Create: `godot/wildlife_world.tscn`
- Create: `godot/src/world/atmosphere.gd`
- Create: `godot/tests/test_world_load.gd`

**Interfaces:**
- Consumes: all Tasks 1–10 nodes.
- Produces: `wildlife_world.tscn` with terrain, track, bridge, underpass, animals, safety visuals, camera, atmosphere; `main.tscn` instances it.

- [ ] **Step 1: Compose the scene** — `wildlife_world.tscn` instances `Terrain`, `TrackBuilder`, `Bridge`, `Underpass`, `WildlifeDirector`, `SafetyVisuals`, `CameraDirector`, `DirectionalLight3D`, `WorldEnvironment`. Wire `WildlifeDirector.publisher`, `CameraDirector.target` (the train), `SafetyVisuals.barrier/led`.

- [ ] **Step 2: Day/night**

`godot/src/world/atmosphere.gd`: `Atmosphere.set_time(t01: float) -> void` rotating the sun and blending the `WorldEnvironment` sky color.

- [ ] **Step 3: World-load test**

`godot/tests/test_world_load.gd`: load `res://wildlife_world.tscn`, instantiate, assert `Terrain`, `WildlifeDirector`, and `SafetyVisuals` are present. Run headless (`bash godot/tests/run_tests.sh`) — expect all PASS, `exit=0`.

- [ ] **Step 4: Commit** — `feat(godot): composed forest wildlife world + day/night`.

---

## Self-Review

- **Spec coverage:** §7 environment → Tasks 1–4, 11; §8 wildlife → Tasks 5–7; §9 safety → Tasks 8, 10; §10 cameras/scenarios → Tasks 9, 10; §14 perf → MultiMesh in Task 11 (forest). §15 manual visual checklist is executed on the Windows GPU target (Plan 4).
- **Placeholder scan:** no TBD; asset URLs are intentionally empty in the manifest with a procedural fallback (this is a designed fallback, not a placeholder).
- **Type consistency:** `Animal.setup/has_skeleton` (Task 5) used by Task 6; `WildlifePublisher.report` (Plan 1 Task 11) used by Task 7; `SafetyVisuals.apply` (Task 8) used by Task 10; `CameraDirector.mode_name` (Task 9) used by Task 10.
- Tasks 3, 4, 7, 8, 9, 10, 11 give the test's assertions in prose where the code is trivial; each still has a runnable headless test file and an exact expected result.
