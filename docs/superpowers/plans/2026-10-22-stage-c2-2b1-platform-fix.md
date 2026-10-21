# Stage 2B.1 — Island Platform Localization Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all five island platform modules identical, level, centred between the rails, with benches, bins, signs and posts resting on the platform surface.

**Architecture:** Replace the auto-fit `_fit_platform` shrink (which measured world-space AABB corners projected onto the radial axis — rotation inflated it differently at every track angle, giving five different scales 0.18–0.33 and tops between −0.80 m and −0.42 m) with a deterministic placer that measures the asset in its own local frame once and applies one locked non-uniform scale so every module is exactly 9.6 m long × 2.2 m wide × 1.8 m tall with its top at +0.55 m and bottom at −1.25 m relative to the rail.

**Tech Stack:** Godot 4.7 GDScript, existing `SceneryDirector` asset pipeline (`platform.glb`).

**Spec:** `docs/superpowers/specs/2026-10-21-stage-c2-double-track-multitrain-design.md` (§5.1 island station; supersedes the Task 5 `_fit_platform` approach in `docs/superpowers/plans/2026-10-22-stage-c2-2b-double-track-world.md`).

## Global Constraints

- Study capture evidence (2026-10-22): scales 0.18–0.33 per module, tops −0.80…−0.42 m, benches/bins aligned to +0.55 m float in mid-air; captured in `/tmp/opencode/platform_before_*.png`.
- Every module must satisfy: pose-space size 9.6 × 1.8 × 2.2 m; top +0.55 m; bottom −1.25 m; lateral half-extent ≤ 1.15 m; centre within 0.8 m of the UP/DOWN midpoint.
- The asset's `Cylinder_001` railing child must be removed (it is 15.1 m long — it would overlap between modules and z-fight).
- Keep the full Godot suite green (22/22) — especially `test_station_island.gd` and `test_station_crossovers.gd`.
- All platform geometry is built at runtime in `SceneryDirector`; no scene-file changes.

---

### Task 1: Deterministic platform modules

**Files:**
- Modify: `godot/tests/test_station_island.gd` (append assertions inside `_run`)
- Modify: `godot/src/scenery_director.gd` (replace `_fit_platform`, add `_place_platform_module` and `_local_mesh_aabb`, constants)
- Test: `godot/tests/test_station_island.gd`

**Interfaces:**
- Consumes: `LTSTrack.get_global_transform_at_distance(distance) -> Transform3D`; existing `_spawn`, `_align_bottom`, `_world_aabb`.
- Produces: `SceneryDirector.PLATFORM_LENGTH_M = 9.6`, `PLATFORM_WIDTH_M = 2.2`, `PLATFORM_TOP_M = 0.55`, `PLATFORM_BOTTOM_M = -1.25`; `_place_platform_module(mid: Transform3D) -> Node3D`; `_local_mesh_aabb(root: Node3D) -> AABB`. Task 2 (captures) and later 2C–2D slices rely on `Platform0..4` world transforms staying at rail level +0.55.

- [x] **Step 1: Write the failing test assertions**

Append to `_run()` in `godot/tests/test_station_island.gd`, directly before `scene.queue_free()`:

```gdscript
	var platform_tops: Array[float] = []
	for module in 5:
		var platform := scenery.get_node_or_null("Platform%d" % module) as Node3D
		if platform == null:
			continue
		var d_up: float = scenery.station_distance + module * scenery.station_module_spacing
		var up_pose: Transform3D = up.get_global_transform_at_distance(d_up)
		var down_pose: Transform3D = down.get_global_transform_at_distance(d_up * down.length / up.length)
		var mid := up_pose
		mid.origin = (up_pose.origin + down_pose.origin) * 0.5
		var local_box := _world_aabb_in(platform, mid.affine_inverse())
		a.ok(absf(local_box.size.x - 9.6) < 0.15, "module %d is 9.6 m long" % module)
		a.ok(absf(local_box.size.z - 2.2) < 0.15, "module %d is 2.2 m wide" % module)
		var world_box := _world_aabb(platform)
		var top: float = world_box.end.y
		var bottom: float = world_box.position.y
		platform_tops.append(top)
		a.ok(absf(top - (mid.origin.y + 0.55)) < 0.06, "module %d top rests at 0.55 m" % module)
		a.ok(absf(bottom - (mid.origin.y - 1.25)) < 0.06, "module %d bottom sits at -1.25 m" % module)

	for bench in scenery.find_children("Bench*", "", true, false):
		var fixture := bench as Node3D
		var bottom := _world_aabb(fixture).position.y
		var rests := false
		for top in platform_tops:
			if absf(top - bottom) < 0.06:
				rests = true
		a.ok(rests, "bench rests on a platform top")
	a.ok(scenery.find_children("Bench*", "", true, false).size() >= 2, "both benches exist")

	for bin_node in scenery.find_children("Bin*", "", true, false):
		var fixture := bin_node as Node3D
		var bottom := _world_aabb(fixture).position.y
		var rests := false
		for top in platform_tops:
			if absf(top - bottom) < 0.06:
				rests = true
		a.ok(rests, "bin rests on a platform top")
	a.ok(scenery.find_children("Bin*", "", true, false).size() >= 2, "both bins exist")
```

Patterns use `Bench*` / `Bin*` because Godot replaces clashing duplicate sibling names with non-readable ones (`@Node3D@85`), so matching on the asset name would silently miss the second fixture. The implementation therefore names the fixtures deterministically (`Bench1`, `Bench3`, `Bin1`, `Bin3`) as part of Step 3.

Add this helper next to `_world_aabb`:

```gdscript
func _world_aabb_in(root: Node3D, transform: Transform3D) -> AABB:
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
			var point := transform * (mesh_instance.global_transform * box.get_endpoint(index))
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result
```

- [x] **Step 2: Run test to verify it fails**

Run: `timeout 90 /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_station_island.gd 2>&1 | grep -E "^(PASS|FAIL)" | sort | uniq -c`

Expected: `FAIL test_station_island`, with failures like "module 0 is 9.6 m long", "module 0 top rests at 0.55 m", "bench rests on a platform top".

- [x] **Step 3: Write the implementation**

In `godot/src/scenery_director.gd`:

Add constants after the exports:

```gdscript
const PLATFORM_LENGTH_M := 9.6
const PLATFORM_WIDTH_M := 2.2
const PLATFORM_TOP_M := 0.55
const PLATFORM_BOTTOM_M := -1.25
```

Delete `_fit_platform` entirely and replace with:

```gdscript
func _place_platform_module(mid: Transform3D) -> Node3D:
	var platform := _spawn("platform", mid)
	if platform == null:
		return null
	var railing := platform.get_node_or_null("Cylinder_001")
	if railing:
		platform.remove_child(railing)
		railing.queue_free()
	var box := _local_mesh_aabb(platform)
	if box.size.x < 0.01 or box.size.y < 0.01 or box.size.z < 0.01:
		return platform
	var module_scale := Vector3(
		PLATFORM_LENGTH_M / box.size.x,
		(PLATFORM_TOP_M - PLATFORM_BOTTOM_M) / box.size.y,
		PLATFORM_WIDTH_M / box.size.z)
	platform.scale = module_scale
	platform.global_position = mid.origin - mid.basis * (box.get_center() * module_scale)
	_align_bottom(platform, mid.origin.y + PLATFORM_BOTTOM_M)
	return platform


func _local_mesh_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for item in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := item as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var transform := root.global_transform.affine_inverse() * mesh_instance.global_transform
		var box := mesh_instance.get_aabb()
		for index in 8:
			var point := transform * box.get_endpoint(index)
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result
```

In `_build_station()`, replace:

```gdscript
		var platform := _spawn("platform", mid)
		if platform:
			platform.name = "Platform%d" % module
			_fit_platform(platform, mid, 2.2)
			_align_bottom(platform, mid.origin.y - 1.25)
```

with:

```gdscript
		var platform := _place_platform_module(mid)
		if platform:
			platform.name = "Platform%d" % module
```

and change `var platform_top := 0.55` to `var platform_top := PLATFORM_TOP_M` so benches and bins share the single source of truth.

Also give the fixtures deterministic names, because Godot replaces the second duplicate sibling name with a non-readable one (`@Node3D@85`), so the asset-derived `bench` / `garbage` name survives only on the first fixture:

```gdscript
		if module in [1, 3]:
			var bench_pose := mid
			bench_pose.origin += bench_pose.basis.x * 4.0
			var bench := _spawn("bench", bench_pose)
			if bench:
				bench.name = "Bench%d" % module
				_align_bottom(bench, mid.origin.y + platform_top)
			var bin := _spawn("garbage", bench_pose)
			if bin:
				bin.name = "Bin%d" % module
				bin.global_position += bench_pose.basis.x * 1.6
				_align_bottom(bin, mid.origin.y + platform_top)
```

- [x] **Step 4: Run tests to verify they pass**

Run: `timeout 90 /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/test_station_island.gd 2>&1 | grep -E "^(PASS|FAIL)"`
Expected: `PASS test_station_island`

Then run: `timeout 420 bash godot/tests/run_tests.sh 2>&1 | grep -cE "^PASS"` → `22`, and `... | grep -c FAIL` → `0`.

- [x] **Step 5: Commit**

```bash
git add godot/src/scenery_director.gd godot/tests/test_station_island.gd
git commit -m "fix(godot): deterministic island platform placement"
```

---

### Task 2: Visual verification and evidence

**Files:**
- Create: `godot/tests/capture_station.gd`
- Modify: `docs/porting/acceptance.md` (Stage 2B table row)

**Interfaces:**
- Consumes: `Platform0..4` from Task 1; existing capture conventions (`RenderingServer.force_draw`, `root.get_texture().get_image().save_png`).
- Produces: `/tmp/opencode/platform_after_topdown.png`, `/tmp/opencode/platform_after_oblique.png`.

- [x] **Step 1: Create the capture script**

Create `godot/tests/capture_station.gd`:

```gdscript
extends SceneTree

## Run: xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 \
##        --path godot --resolution 1280x720 --rendering-method gl_compatibility \
##        --script res://tests/capture_station.gd

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
	camera.global_position = Vector3(34.0, 50.0, -231.0)
	camera.look_at(Vector3(34.0, 0.0, -231.0), Vector3(0.0, 0.0, -1.0))
	camera.make_current()
	for frame in 3:
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/opencode/platform_after_topdown.png")
	camera.global_position = Vector3(75.0, 14.0, -252.0)
	camera.look_at(Vector3(30.0, 0.0, -231.0), Vector3.UP)
	for frame in 3:
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/opencode/platform_after_oblique.png")
	quit()
```

- [x] **Step 2: Capture and inspect**

Run: `timeout 180 xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --path godot --resolution 1280x720 --rendering-method gl_compatibility --script res://tests/capture_station.gd`

Expected: both PNGs exist and are non-zero. Inspect: five identical modules forming one continuous island with a level top; benches, bins and sign posts resting on the deck; no module crossing a rail.

- [x] **Step 3: Update the acceptance doc**

In `docs/porting/acceptance.md`, extend the Stage 2B "Island station" row to read:

```markdown
| Island station | `test_station_island.gd`: five identical 9.6 × 1.8 × 2.2 m modules centred between the rails inside `UP-B2`/`DOWN-B2`, tops level at +0.55 m, benches/bins on the deck (`2B.1`); captures `platform_after_topdown.png`, `platform_after_oblique.png` |
```

- [x] **Step 4: Commit**

```bash
git add godot/tests/capture_station.gd docs/porting/acceptance.md
git commit -m "docs(c2): verify island platform localization with captures"
```

---

## Stage 2B.1 Exit Gate

- All five modules identical and level: pose-space 9.6 × 1.8 × 2.2 m, top +0.55 m, bottom −1.25 m (`test_station_island.gd`).
- Benches and bins rest on a platform top (`test_station_island.gd`).
- Full Godot suite green (22/22) including crossover clearance (`test_station_crossovers.gd`).
- Visual captures show one continuous island between the rails (`platform_after_*.png`).
