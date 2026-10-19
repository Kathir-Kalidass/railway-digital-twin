# Stage C2 — Godot Twin Visuals, Assets, Animation & Cinematic Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the C1 correctness build into a visually rich, realistic-looking real-time twin: full quality tiers, day/night + weather, PBR environment, hybrid curated hero assets (rigged train/animals) with `AnimationTree` blends, detailed rolling-stock animation, a data-driven scenario director, audio, and a cinematic reel.

**Architecture:** All additions consume the **authoritative** `TwinState` produced in C1; none derive or publish authority. New scene systems (`render_settings`, `atmosphere_controller`, `asset_registry`, `audio_director`, `scenario_director`) plug into the existing composition root. Every system **degrades gracefully** when an imported asset is absent, so `godot --headless` correctness and CI never depend on downloaded assets.

**Tech Stack:** Godot 4.7 (Forward+/Vulkan on the Windows GPU demo target), GDScript, glTF/`.glb` imported assets, `AnimationTree` (`AnimationNodeStateMachine`), `SkeletonIK3D`, `MultiMeshInstance3D`, `WorldEnvironment`/`Environment`, `AudioStreamPlayer3D`.

**Spec:** [`../specs/2026-10-19-stage-c-godot-digital-twin-design.md`](../specs/2026-10-19-stage-c-godot-digital-twin-design.md)

**Prerequisite:** C1 (`2026-10-19-stage-c-godot-twin-integration.md`) complete — this plan builds on `TwinState`, `MqttBridge`, `track_builder.block_map()`, and the composition root.

## Global Constraints

- **Authority is unchanged from C1.** Godot still publishes only `railway/zoneN/wildlife` and never derives aspects, occupancy, trains, or commands.
- **Asset licensing:** only CC0 / CC-BY (or an equally permissive, OSI-compatible license verified per asset). Every imported asset is recorded in `godot/assets/CREDITS.md` (name, author, source URL, license name + URL, modifications). No copyrighted or unclear-license assets.
- **Asset-optional:** the project must load and pass all headless checks with **zero** imported assets present. `asset_registry.gd` returns a procedural placeholder when a file is missing.
- **No placeholder URLs in code:** asset paths are config/resource-driven (`asset_registry.gd`), not hard-coded to specific third-party URLs.
- **Determinism:** procedural world/vegetation uses the fixed seed from config.
- **Performance:** 60 FPS @ 1080p High on mid-range GPU; 30 FPS floor Low; auto-knockdown one tier if frame time exceeds budget for a sustained window.
- **Sim disclaimer** stays visible in the HUD and cinematic reel.
- **Beauty is Windows-GPU only.** WSL runs headless parse/contract checks; visual acceptance is a documented Windows checklist item, recorded as *not run* if unavailable.

## File Structure

- Create `godot/scripts/render_settings.gd` — quality-tier + post-processing application.
- Create `godot/scripts/atmosphere_controller.gd` — day/night + weather.
- Create `godot/scripts/asset_registry.gd` — asset lookup with procedural fallback.
- Create `godot/scripts/audio_director.gd` — spatial audio + mute.
- Create `godot/scripts/scenario_director.gd` — data-driven scenario playback.
- Create `godot/scenarios/*.json` — scenario content (safety/ops/cinematic).
- Create `godot/assets/CREDITS.md` — license manifest (extends C1 placeholder).
- Modify `godot/scripts/world_builder.gd`, `train_controller.gd`, `wildlife_controller.gd`, `camera_director.gd`, `hud.gd`.
- Modify `godot/main.gd` — wire new systems.
- Modify `godot/tests/run_headless.gd` — new headless tests.

---

### Task 1: Full quality tiers and post-processing

**Files:**
- Create: `godot/scripts/render_settings.gd`
- Create: `godot/tests/test_render_settings.gd`
- Modify: `godot/main.gd`, `godot/tests/run_headless.gd`

**Interfaces:**
- Produces: `RenderSettings` (`RefCounted`) with `apply(env: Environment, tier: String) -> void`, `tier_from_config(cfg: AppConfig) -> String`, and `next_lower(tier: String) -> String`.
- Consumes: `AppConfig.renderer_quality`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/test_render_settings.gd`:

```gdscript
class_name TestRenderSettings
extends RefCounted

static func run() -> Array:
	var failures: Array[String] = []
	var rs = load("res://scripts/render_settings.gd").new()
	if rs.next_lower("high") != "medium": failures.append("high->medium")
	if rs.next_lower("medium") != "low": failures.append("medium->low")
	if rs.next_lower("low") != "low": failures.append("low floor")
	var env := Environment.new()
	rs.apply(env, "high")
	if env.ssao_enabled != true: failures.append("high ssao")
	rs.apply(env, "low")
	if env.ssao_enabled != false: failures.append("low ssao")
	return failures
```

Append `failures.append_array(TestRenderSettings.run())` to `run_headless.gd`.

- [ ] **Step 2: Run to verify it fails**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/run_headless.gd`
Expected: FAIL (`render_settings.gd` not found).

- [ ] **Step 3: Implement `render_settings.gd`**

```gdscript
class_name RenderSettings
extends RefCounted

const TIERS := ["high", "medium", "low"]

func tier_from_config(cfg: AppConfig) -> String:
	return cfg.renderer_quality if TIERS.has(cfg.renderer_quality) else "high"

func next_lower(tier: String) -> String:
	var i := TIERS.find(tier)
	return TIERS[min(i + 1, TIERS.size() - 1)] if i >= 0 else "low"

func apply(env: Environment, tier: String) -> void:
	env.ssao_enabled = tier != "low"
	env.ssil_enabled = tier == "high"
	env.ssr_enabled = tier == "high"
	env.glow_enabled = tier != "low"
	env.volumetric_fog_enabled = tier != "low"
	env.fog_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if tier == "high" else Environment.TONE_MAPPER_FILMIC
	env.fog_light_energy = 0.6 if tier != "low" else 0.2
```

- [ ] **Step 4: Wire into `main.gd`**

Create the `WorldEnvironment` + `Environment` once, call `render_settings.apply(env, tier)`, and expose a `set_tier(tier)` hook used by the auto-knockdown (Task 10).

- [ ] **Step 5: Run test, expect pass**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/run_headless.gd`
Expected: `PASS run_headless`.

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/render_settings.gd godot/tests/test_render_settings.gd godot/main.gd godot/tests/run_headless.gd
git commit -m "feat(godot): quality tiers and post-processing presets"
```

---

### Task 2: Day/night cycle and weather

**Files:**
- Create: `godot/scripts/atmosphere_controller.gd`
- Create: `godot/tests/test_atmosphere.gd`
- Modify: `godot/main.gd`, `godot/tests/run_headless.gd`

**Interfaces:**
- Produces: `AtmosphereController extends Node3D` with `build(parent)`, `set_preset(day: bool, weather: String)`, `cycle_daynight() -> void`, `cycle_weather() -> void`, `update(delta)`, and read-only `weather`/`is_day`.
- Consumes: `AppConfig` `[simulation] day_night, weather`.

- [ ] **Step 1: Write the failing test**

```gdscript
class_name TestAtmosphere
extends RefCounted

static func run() -> Array:
	var failures: Array[String] = []
	var a = load("res://scripts/atmosphere_controller.gd").new()
	if not a.VALID_WEATHER.has("fog") or not a.VALID_WEATHER.has("rain"): failures.append("weather enum")
	a.set_preset(false, "rain")
	if a.weather != "rain" or a.is_day != false: failures.append("preset apply")
	if a.next_weather("clear") == "clear": failures.append("cycle")
	a.free()
	return failures
```

- [ ] **Step 2: Run to verify it fails**

Run the headless harness. Expected: FAIL (`atmosphere_controller.gd` not found).

- [ ] **Step 3: Implement**

```gdscript
class_name AtmosphereController
extends Node3D

const VALID_WEATHER := ["clear", "fog", "rain"]
var is_day: bool = true
var weather: String = "clear"
var _sun: DirectionalLight3D
var _auto: bool = false
var _t: float = 0.0

func build(parent: Node3D) -> void:
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)
	parent.add_child(self)

func set_preset(day: bool, w: String) -> void:
	is_day = day
	weather = w if VALID_WEATHER.has(w) else "clear"
	_apply()

func cycle_daynight() -> void:
	is_day = not is_day
	_apply()

func cycle_weather() -> void:
	set_preset(is_day, next_weather(weather))

func next_weather(cur: String) -> String:
	var i := VALID_WEATHER.find(cur)
	return VALID_WEATHER[(i + 1) % VALID_WEATHER.size()]

func _apply() -> void:
	var angle := 55.0 if is_day else -10.0
	_sun.rotation_degrees = Vector3(-angle, 25.0, 0.0)
	_sun.light_energy = 1.1 if is_day else 0.15
	_sun.light_color = Color(1.0, 0.96, 0.9) if is_day else Color(0.55, 0.6, 0.85)

func update(delta: float) -> void:
	if _auto:
		_t += delta * 0.01
		_sun.rotation_degrees.y = fmod(_t, 360.0)
```

Weather particle/fog-density detail is applied in Task 3 with the environment; `set_preset` stores the intent so the environment reads it in the same frame.

- [ ] **Step 4: Wire `N`/`W` inputs in `main.gd`** to `cycle_daynight()`/`cycle_weather()` and pass the preset to the environment.

- [ ] **Step 5: Run test, expect pass; headless load check**

Run the harness then `--headless --editor --path godot --quit`. Expected `PASS run_headless`; no errors.

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/atmosphere_controller.gd godot/tests/test_atmosphere.gd godot/main.gd godot/tests/run_headless.gd
git commit -m "feat(godot): day/night and weather system"
```

---

### Task 3: Environment upgrade — sky, fog, weather response, PBR vegetation batching

**Files:**
- Modify: `godot/scripts/world_builder.gd`, `godot/main.gd`
- Modify: `godot/scripts/atmosphere_controller.gd`
- Create: `godot/assets/CREDITS.md` (if not present)

**Interfaces:**
- Produces: `WorldBuilder.build_environment(parent, env: Environment)` applying a `Sky` (procedural `ProceduralSkyMaterial` by default, optional imported HDRI via `AssetRegistry`), fog density/energy driven by `AtmosphereController`, and `build_forest(parent, topology)` using `MultiMeshInstance3D` for trees/grass with LOD.

- [ ] **Step 1: Implement sky + fog response**

Add `apply_weather(w, env)` to `atmosphere_controller.gd`: `clear` → low fog density; `fog` → high fog density + reduced `fog_light_energy`; `rain` → mid fog + enable a `GPUParticles3D` rain emitter parented to the camera and a wet-look roughness tweak on terrain. HDRI, if registered, replaces the `ProceduralSkyMaterial`.

- [ ] **Step 2: Convert vegetation to MultiMesh**

In `build_forest`, build tree-trunk/tree-canopy/grass `MultiMesh` instances with `instance_count` from config, seeded by the fixed seed, `visibility_range_end` LOD, and no per-instance scripts. Cap total instances by tier (High > Medium > Low).

- [ ] **Step 3: Headless load check**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path godot --quit 2>&1 | grep -iE "error|parse"`
Expected: no errors (procedural sky path, no HDRI required).

- [ ] **Step 4: Commit**

```bash
git add godot/scripts/world_builder.gd godot/scripts/atmosphere_controller.gd godot/main.gd godot/assets/CREDITS.md
git commit -m "feat(godot): pbr sky, weather fog, batched vegetation"
```

---

### Task 4: Hero assets — vendoring, licensing manifest, and fallback registry

**Files:**
- Create: `godot/scripts/asset_registry.gd`
- Create: `godot/tests/test_asset_registry.gd`
- Modify: `godot/assets/CREDITS.md`
- Create (optional, license-verified): `godot/assets/hero/*.glb`

**Interfaces:**
- Produces: `AssetRegistry` (static-ish) with `register(id: String, path: String)`, `instantiate(id: String) -> Node3D` returning an imported scene when present, otherwise a procedural placeholder; `has(id: String) -> bool`.
- Consumes: C1 procedural builders as placeholders.

**Asset-sourcing rules (do this before writing `CREDITS.md`):**
- Candidates are CC0/CC-BY only. Acceptable sources include (verify the license **on the asset's own page** before use): Poly Haven (CC0 HDRIs/textures/models), Quaternius (CC0 models incl. rigged animals/vehicles), Kenney (CC0 kits), and Sketchfab filtered to CC0/CC-BY. For each candidate record the asset page URL and the license line verbatim.
- **Timebox:** if no license-clean rigged asset for a role (locomotive, coach, elephant, deer) is found within the task's timebox, keep the procedural placeholder, mark the role `deferred` in `CREDITS.md`, and continue. Do not use an unclear-license asset "just for the demo".
- Prefer `.glb` (single-file glTF) with an embedded skeleton and animation clips.

- [ ] **Step 1: Write the failing test**

```gdscript
class_name TestAssetRegistry
extends RefCounted

static func run() -> Array:
	var failures: Array[String] = []
	var reg = load("res://scripts/asset_registry.gd").new()
	if reg.has("elephant"): failures.append("should be unregistered by default")
	var placeholder = reg.instantiate("elephant")
	if placeholder == null: failures.append("placeholder fallback")
	if not placeholder.is_class("Node3D"): failures.append("placeholder type")
	return failures
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL (`asset_registry.gd` not found).

- [ ] **Step 3: Implement `asset_registry.gd`**

```gdscript
class_name AssetRegistry
extends RefCounted

var _paths: Dictionary = {}

func register(id: String, path: String) -> void:
	if ResourceLoader.exists(path):
		_paths[id] = path

func has(id: String) -> bool:
	return _paths.has(id)

func instantiate(id: String) -> Node3D:
	if _paths.has(id):
		var packed := load(_paths[id])
		if packed is PackedScene:
			var n := packed.instantiate()
			if n is Node3D:
				return n
	return _placeholder(id)

func _placeholder(id: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Placeholder_%s" % id
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	n.add_child(mesh)
	return n
```

`main.gd` calls `register(...)` for each hero asset whose file exists, so `AssetRegistry` is populated only when the asset was vendored.

- [ ] **Step 4: Vendor assets and write `CREDITS.md`**

For each role with a verified asset, place the `.glb` under `godot/assets/hero/`, and add a `CREDITS.md` row. Template row:

```markdown
| Role | File | Author | Source URL | License | License URL | Modifications |
|------|------|--------|-----------|---------|-------------|---------------|
| elephant | hero/elephant.glb | <author> | <asset-page-url> | CC0 1.0 | https://creativecommons.org/publicdomain/zero/1.0/ | rescaled, retargeted clips |
```

Also record imported HDRI/textures here. Roles with no clean asset get a `deferred` row.

- [ ] **Step 5: Run test, expect pass; headless load check with and without assets**

Run the harness (expect `PASS`), then temporarily confirm the project still loads with `godot/assets/hero/` empty (the CI guarantee).

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/asset_registry.gd godot/tests/test_asset_registry.gd godot/assets/CREDITS.md godot/assets/hero
git commit -m "feat(godot): hero asset registry with licensing manifest and fallback"
```

---

### Task 5: Skeletal wildlife with AnimationTree, IK, and root motion

**Files:**
- Modify: `godot/scripts/wildlife_controller.gd`
- Modify: `godot/main.gd`

**Interfaces:**
- Produces: `WildlifeActor` (scene/node wrapping an imported rig) with states `idle, graze, approach, crossing, alarm, flee, stopped`; herd instancing; `SkeletonIK3D` foot placement; root motion extracted to move the actor; existing `set_visible_zone1/2` and telemetry triggers retained.
- Consumes: `AssetRegistry.instantiate("elephant"|"deer")`, `AtmosphereController.is_day`.

- [ ] **Step 1: Build the state machine per actor**

For each instantiated rig, create an `AnimationTree` with an `AnimationNodeStateMachine`. Map clips: `idle→idle`, `walk→approach/crossing`, `run→flee`, plus `graze`, `alarm`, `stopped` (use the closest available clip and rename in the tree if the asset's clip names differ; document any remap in `CREDITS.md` modifications column). Blend `idle↔walk↔run` with a `BlendSpace1D` on speed.

- [ ] **Step 2: IK + root motion**

Add a `SkeletonIK3D` per foot targeting a raycast onto the terrain/road surface; enable root motion (or read the animation's root displacement and translate the actor) so walk/run cycles translate without sliding. When the asset is the procedural placeholder, skip IK and drive a simple leg bob so no errors occur.

- [ ] **Step 3: Trigger wiring**

Wildlife start/clear (from `set_visible_zone1/2` and the scenario director) drive `approach → crossing → (alarm) → flee → idle`; the **hazard/aspect remains backend-authoritative** and only influences the actor via the rendered signal (e.g., an approaching train with `RED`/`YELLOW` triggers `alarm`/`flee`).

- [ ] **Step 4: Headless load check**

Run the `--headless --editor` gate. Expected: no errors (placeholder path).

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/wildlife_controller.gd godot/main.gd
git commit -m "feat(godot): skeletal wildlife animation tree, ik, root motion"
```

---

### Task 6: Rolling-stock detail animation

**Files:**
- Modify: `godot/scripts/train_controller.gd`
- Modify: `godot/main.gd`

**Interfaces:**
- Produces: consist detail — articulated bogies, couplers, brake sparks on deceleration, exhaust/steam, head/tail lamps, speed-synced wheel rotation, suspension bob; smooth position/velocity interpolation from authoritative `block`+`offsetM`+`speedKmh`.

- [ ] **Step 1: Interpolate with velocity and heading**

Derive per-frame target arc-length from the authoritative block transform + `offsetM`; compute velocity from the delta of positions over the state interval (never from a local simulation); apply wheel rotation proportional to path speed and suspension bob as a damped spring.

- [ ] **Step 2: Effects gated by authority**

Brake sparks fire only when the *authoritative* speed is decreasing (compare successive `speedKmh`); steam/exhaust scaled by speed; lamps always on; tail lamp at the consist end. No effect may imply a capability not present in state.

- [ ] **Step 3: Headless load check**

Run the `--headless --editor` gate. Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add godot/scripts/train_controller.gd godot/main.gd
git commit -m "feat(godot): detailed rolling-stock animation and effects"
```

---

### Task 7: Scenario director and scenario data format

**Files:**
- Create: `godot/scripts/scenario_director.gd`
- Create: `godot/tests/test_scenario_director.gd`
- Modify: `godot/main.gd`, `godot/tests/run_headless.gd`

**Interfaces:**
- Produces: `ScenarioDirector` with `load_scenario(id: String) -> Dictionary`, `start()`, `stop()`, `advance(delta)`, signals `observation_triggered(zone: String, detected: bool)`, `atmosphere_requested(day: bool, weather: String)`, `camera_requested(shot: String)`.
- Scenario schema (JSON): `{ "id", "title", "loop", "duration", "tracks": { "camera": [{"t":0,"shot":"chase"}], "atmosphere": [{"t":0,"day":true,"weather":"clear"}], "observation": [{"t":12,"zone":"zone1","detected":true}], "audio": [{"t":5,"cue":"horn"}] } }`.

- [ ] **Step 1: Write the failing test**

```gdscript
class_name TestScenarioDirector
extends RefCounted

static func run() -> Array:
	var failures: Array[String] = []
	var sd = load("res://scripts/scenario_director.gd").new()
	var s := {"id":"x","duration":10.0,"tracks":{"camera":[{"t":0.0,"shot":"chase"}],"observation":[{"t":2.0,"zone":"zone1","detected":true}]}}
	if not sd.load_scenario_dict(s): failures.append("load dict")
	if sd.total_duration() != 10.0: failures.append("duration")
	var fired: Array = []
	sd.observation_triggered.connect(func(z, d): fired.append([z, d]))
	sd.start()
	sd.advance(3.0)
	if fired.is_empty() or fired[0][0] != "zone1": failures.append("trigger fired")
	return failures
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL (`scenario_director.gd` not found).

- [ ] **Step 3: Implement**

```gdscript
class_name ScenarioDirector
extends RefCounted

signal observation_triggered(zone: String, detected: bool)
signal atmosphere_requested(day: bool, weather: String)
signal camera_requested(shot: String)
signal audio_cue(cue: String)
signal finished()

var _s: Dictionary = {}
var _t: float = 0.0
var _playing: bool = false
var _fired: Dictionary = {}

func load_scenario(id: String) -> Dictionary:
	var path := "res://scenarios/%s.json" % id
	if not FileAccess.file_exists(path):
		return {}
	return load_scenario_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))

func load_scenario_dict(d) -> bool:
	if typeof(d) != TYPE_DICTIONARY or not d.has("duration"):
		return false
	_s = d
	_t = 0.0
	_fired.clear()
	return true

func total_duration() -> float:
	return float(_s.get("duration", 0.0))

func start() -> void:
	_t = 0.0
	_fired.clear()
	_playing = true

func stop() -> void:
	_playing = false

func advance(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	var tracks: Dictionary = _s.get("tracks", {})
	_emit_due("observation", tracks, func(e): observation_triggered.emit(str(e.get("zone","")), bool(e.get("detected", false))))
	_emit_due("atmosphere", tracks, func(e): atmosphere_requested.emit(bool(e.get("day", true)), str(e.get("weather","clear"))))
	_emit_due("camera", tracks, func(e): camera_requested.emit(str(e.get("shot",""))))
	_emit_due("audio", tracks, func(e): audio_cue.emit(str(e.get("cue",""))))
	if _t >= total_duration() and not bool(_s.get("loop", false)):
		_playing = false
		finished.emit()

func _emit_due(kind: String, tracks: Dictionary, cb: Callable) -> void:
	for e in tracks.get(kind, []):
		var key := "%s:%s:%s" % [kind, str(e.get("t",0.0)), str(e)]
		if float(e.get("t", 0.0)) <= _t and not _fired.has(key):
			_fired[key] = true
			cb.call(e)
```

- [ ] **Step 4: Wire `P`/`Esc` in `main.gd`**: `P` advances/plays the loaded scenario; `Esc` stops. Connect `observation_triggered` → `wildlife` + `bridge.publish_wildlife`, `atmosphere_requested` → `atmosphere`, `camera_requested` → `camera_director`, `audio_cue` → `audio_director`.

- [ ] **Step 5: Run test, expect pass; headless load check**

Expected: `PASS run_headless`; no errors.

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/scenario_director.gd godot/tests/test_scenario_director.gd godot/main.gd godot/tests/run_headless.gd
git commit -m "feat(godot): data-driven scenario director"
```

---

### Task 8: Scenario content — safety, ops, and cinematic reel

**Files:**
- Create: `godot/scenarios/safety_wildlife_dusk.json`, `safety_sensor_fault.json`, `safety_comm_loss.json`, `safety_recovery.json`
- Create: `godot/scenarios/ops_meet_pass.json`, `ops_signal_progression.json`, `ops_tunnel_bridge.json`, `ops_emergency_brake.json`
- Create: `godot/scenarios/cinematic_reel.json`

**Interfaces:**
- Consumes: `ScenarioDirector` schema (Task 7).
- **Authority caveat:** scenarios trigger only Godot-local **wildlife** observations. Backend-authoritative actions (reset, speed, hazard clear, sensor fault) are **not** scripted here; the ops/safety scenarios assume the operator drives those from the dashboard, and the cinematic reel only uses cameras/atmosphere/audio + wildlife observations.

- [ ] **Step 1: Author the safety scenarios**

Each is a timeline: camera + atmosphere, and (where appropriate) a wildlife observation trigger. Example `safety_wildlife_dusk.json`:

```json
{ "id": "safety_wildlife_dusk", "title": "Wildlife near-miss at dusk", "loop": false, "duration": 40.0,
  "tracks": {
    "atmosphere": [ {"t":0,"day":false,"weather":"fog"} ],
    "camera": [ {"t":0,"shot":"crossing"}, {"t":18,"shot":"chase"} ],
    "observation": [ {"t":8,"zone":"zone1","detected":true}, {"t":24,"zone":"zone1","detected":false} ]
  } }
```

`safety_sensor_fault.json`/`safety_recovery.json` use camera/atmosphere only and are documented as requiring **dashboard-driven** `SENSOR_FAULT`/reset (put this in a `"notes"` field). `safety_comm_loss.json` is a camera/atmosphere walkthrough documented as requiring a broker restart.

- [ ] **Step 2: Author the ops scenarios**

Camera/atmosphere tracks for meet/pass, signal progression, tunnel/bridge, and emergency braking. `ops_emergency_brake.json` includes a camera track that holds on the consist after the operator commands a stop from the dashboard, so brake sparks/lights are visible. No speed/reset commands are scripted.

- [ ] **Step 3: Author the cinematic reel**

`cinematic_reel.json`: a ~90 s montage of camera shots (overview → chase → cab → crossing → station → tunnel → bridge), atmosphere changes (dawn → day → dusk → rain), audio cues, and one wildlife crossing; ends on a title frame with the sim disclaimer. `"loop": false`.

- [ ] **Step 4: Validate all scenarios load**

Add a loop to `run_headless.gd` that loads every `res://scenarios/*.json` via `ScenarioDirector.load_scenario()` and asserts each returns non-empty with `duration > 0`. Run the harness; expect `PASS run_headless`.

- [ ] **Step 5: Commit**

```bash
git add godot/scenarios godot/tests/run_headless.gd
git commit -m "feat(godot): authored safety, ops, and cinematic scenarios"
```

---

### Task 9: Audio director

**Files:**
- Create: `godot/scripts/audio_director.gd`
- Modify: `godot/main.gd`, `godot/assets/CREDITS.md`

**Interfaces:**
- Produces: `AudioDirector extends Node3D` with `build(parent)`, `play_cue(cue: String)`, `set_muted(bool)`, `attach_emitter(kind: String, node: Node3D)` for positional loops.
- Cues: `horn`, `bell`, `wheel`, `ambience_forest`, `ambience_rain`, `wildlife_alarm`.

- [ ] **Step 1: Implement with graceful absence**

If an audio file is missing (CC0/CC-BY not yet vendored), `play_cue` is a no-op (no errors). Loop emitters for wheel/rail and crossing bell are attached to the relevant nodes; one global mute toggle. Cap concurrent streams.

- [ ] **Step 2: Source audio (license-verified)**

Vendor CC0 (or CC-BY with attribution) audio under `godot/assets/audio/`, adding `CREDITS.md` rows. Roles without clean audio stay silent and are marked `deferred`.

- [ ] **Step 3: Wire `scenario_director.audio_cue` → `audio_director.play_cue`, and `M` (mute) in the input map** (add `mute_audio` action to `project.godot`).

- [ ] **Step 4: Headless load check**

Run the `--headless --editor` gate. Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/audio_director.gd godot/main.gd godot/project.godot godot/assets/CREDITS.md godot/assets/audio
git commit -m "feat(godot): spatial audio director with mute"
```

---

### Task 10: Performance validation, tier auto-knockdown, and docs

**Files:**
- Modify: `godot/scripts/render_settings.gd`, `godot/main.gd`, `README.md`

**Interfaces:**
- Produces: an FPS/frame-time sampler in `main.gd` that, after a sustained window over budget, downgrades one tier via `RenderSettings.next_lower` and logs it; a `README.md` section with the tested machine/resolution and the visual checklist.

- [ ] **Step 1: Implement auto-knockdown**

Track a rolling average of `delta`; if it exceeds the tier's budget (e.g., `> 1/45 s` on High) for ≥3 s, apply `next_lower(tier)` once (never below `low`). Log tier changes without credentials.

- [ ] **Step 2: Document**

Add to `README.md`: the Godot version, the tested Windows GPU + resolution + measured FPS per tier, the input map, scenario ids, and the manual visual checklist (C spec §14.2). Record the WSL/headless checks that were run and the Windows-only checks as *not run* if unavailable.

- [ ] **Step 3: Headless load check + harness**

Run both headless commands. Expected: exit 0; `PASS run_headless`.

- [ ] **Step 4: Commit**

```bash
git add godot/scripts/render_settings.gd godot/main.gd README.md
git commit -m "feat(godot): performance tier auto-knockdown and delivery docs"
```

---

## Self-Review

**Spec coverage:** quality tiers + post-processing (§4 → Task 1); day/night + weather (§4, §10 → Tasks 2–3); hybrid assets + licensing + fallback (§5 → Tasks 3–4, 9); skeletal animation/IK/root motion (§5, §9 → Task 5); rolling stock (§8 → Task 6); scenario director + scenario set (§10 → Tasks 7–8); audio (§10 → Task 9); performance targets/knockdown (§13 → Task 10). MQTT/lifecycle/authority (§2–§3) are C1 and unchanged.

**Placeholder scan:** No `TBD`/`TODO`. The only external unknowns are asset downloads and the exact clip names in an imported rig; both are handled by explicit, verifiable steps (license check + `CREDITS.md`; clip remap documented in the modifications column) with a procedural fallback that keeps the build green. No third-party URLs are hard-coded in code.

**Type consistency:** `RenderSettings`, `AtmosphereController`, `AssetRegistry`, `ScenarioDirector`, `AudioDirector` are referenced consistently; `ScenarioDirector`'s signal names match the wiring in `main.gd`; `AssetRegistry.instantiate` is the single asset entry point used by `wildlife_controller`/`train_controller`.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-19-stage-c-godot-twin-visuals.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks.

**2. Inline Execution** — execute in-session with checkpoints (`superpowers:executing-plans`).

**Note:** tasks with an asset-sourcing step (4, 9) require network access to a CC0/CC-BY provider and human license verification; they are the only tasks that cannot be fully completed headlessly. All others are verifiable in WSL.
