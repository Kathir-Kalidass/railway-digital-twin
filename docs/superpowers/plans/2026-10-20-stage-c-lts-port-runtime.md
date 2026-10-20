# Stage C — LTS Port & Runtime Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a Godot 4.7 project that runs the ported Libre-TrainSim core (rail network + one moving train) and a twin overlay that talks MQTT to the backend, obeys safety/speed overrides, and publishes wildlife observations.

**Architecture:** Two layers in the existing `godot/` project. The **pure-simulation LTS runtime** is ported from Libre-TrainSim's Godot 3 source into `godot/Data/` and `godot/Resources/`; these project-root paths are required by the source's hard-coded `res://Data/...` and `res://Resources/...` references. It exposes a tiny train/track API and knows nothing about MQTT. A **twin overlay** (`godot/src/`) owns MQTT, reads LTS state, and writes only the train target speed (single control entry point).

**Tech Stack:** Godot 4.7 (GDScript, headless testing via `--script`), MQTT (`goatchurchprime/godot-mqtt` addon, MIT), Mosquitto broker in Docker (`docker compose up -d mosquitto`).

**Spec:** `docs/superpowers/specs/2026-10-20-stage-c-libretrainsim-wildlife-design.md`

## Global Constraints

- Engine: Godot **4.7.2** stable at `/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64` (WSL runs headless only). Let `GODOT=/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64` stand for the whole plan.
- Existing project root is `godot/` (Godot 4.7, `config_version=5`). Ported LTS code goes in `godot/Data/` and `godot/Resources/`; overlay code in `godot/src/`. Do not move these directories under `addons/` unless all hard-coded resource paths are rewritten.
- Licensing: the ported core is **GPL v3** — add `godot/LICENSE` and `godot/CREDITS.md`. Non-Godot components are not linked.
- **Never commit** the upstream checkout or its binary assets/caches: no `Libre-TrainSim-master/**`, no `.godot/`, no `*.uid`, no `*.import`, no `*:Zone.Identifier`. The 600MB upstream `Resources/` asset tree remains local and ignored; runtime/test paths must use procedural or optional-resource fallbacks so a clean checkout does not depend on it. Add ignore rules in Task 3.
- MQTT addon `goatchurchprime/godot-mqtt` (MIT), **pinned commit**, vendored under `godot/addons/godot-mqtt/`.
- **Do not modify** (concurrent actor owns these): `mosquitto/*`, `scripts/*`, `docker-compose.yml`, `backend/src/mqtt.js`, `backend/test/{broker_acl,mqtt}.test.js`, `esp32/**`, `README.md`, `.gitignore` (root). Overlay work is confined to `godot/`.
- Brokers: dev TCP `127.0.0.1:1883`, user/pass creds `godot/godot-dev-pass`. Godot subscribes to `railway/state`, `railway/zoneN/signal`, `railway/speed/zoneN`, `railway/commands/zoneN`; publishes only `railway/zoneN/wildlife` and (optional) `railway/trains/{id}`.
- All commits land on `master`.
- Headless verification is the acceptance gate for every task: `bash godot/tests/run_tests.sh` must exit 0.

---

## File Structure

- `godot/tests/run_tests.sh` — runner: imports the project then runs every `godot/tests/test_*.gd` via `--script`; fails fast.
- `godot/tests/test_harness.gd` — base helper (`Assert`) used by tests.
- `godot/tests/test_parse.gd` — loads all ported/overlay scripts and asserts none fail to parse.
- `godot/tests/test_mqtt_bridge.gd` — connects to the Docker broker, round-trips a message, asserts backoff reconnect.
- `godot/tests/test_train_controller.gd` — asserts target-speed override + resume.
- `godot/Data/` and `godot/Resources/` — ported LTS classes and any small source-controlled text resources/scenes required by the runtime. Heavy binary assets remain excluded and must not be required at parse time.
- `godot/src/mqtt_bridge.gd` — MQTT connect/reconnect (exponential backoff) + publish/subscribe.
- `godot/src/twin_state.gd` — parses retained `railway/state`/signal JSON into a typed view.
- `godot/src/train_controller.gd` — single control entry point: `apply_safety(state)` → `set_target_speed_kmh`.
- `godot/src/wildlife_publisher.gd` — debounced publisher for `railway/zoneN/wildlife`.
- `godot/main.tscn` / `godot/main.gd` — rewritten to a minimal composition root (rail + train + overlay). Full world is Plan 2.
- `docs/porting/lts-port.md` — provenance log (file → change → reason).

---

### Task 1: Headless test harness

**Files:**
- Create: `godot/tests/test_harness.gd`
- Create: `godot/tests/test_parse.gd`
- Create: `godot/tests/run_tests.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `Assert` class with `eq(a, b, msg)`, `ok(cond, msg)`, `report()->int`; `run_tests.sh` exit code convention.

- [ ] **Step 1: Write the assert helper**

`godot/tests/test_harness.gd`:

```gdscript
class_name Assert
extends RefCounted

var _failures: Array[String] = []

func ok(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append("ok failed: " + msg)

func eq(a, b, msg: String) -> void:
	if a != b:
		_failures.append("eq failed: %s (got %s, want %s)" % [msg, str(a), str(b)])

func report(name: String) -> int:
	if _failures.is_empty():
		print("PASS ", name)
		return 0
	for f in _failures:
		print("FAIL ", name, ": ", f)
	return 1
```

- [ ] **Step 2: Write the parse smoke test**

`godot/tests/test_parse.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var a := Assert.new()
	var roots := ["res://Data", "res://src", "res://addons"]
	var checked := 0
	for root in roots:
		for path in _gd_files(root):
			var script: GDScript = load(path)
			a.ok(script != null, "loads " + path)
			checked += 1
	a.ok(checked > 0, "found scripts to check")
	quit(a.report("test_parse"))

func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var full := dir_path.path_join(f)
		if d.current_is_dir():
			out.append_array(_gd_files(full))
		elif f.ends_with(".gd"):
			out.append(full)
		f = d.get_next()
	return out
```

- [ ] **Step 3: Write the runner**

`godot/tests/run_tests.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
GODOT="${GODOT:-/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # -> godot/
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
status=0
for t in "$ROOT"/tests/test_*.gd; do
  if ! "$GODOT" --headless --path "$ROOT" --script "res://tests/$(basename "$t")"; then
    status=1
  fi
done
exit $status
```

- [ ] **Step 4: Run it (expect the parse test to fail — ported/overlay dirs are empty)**

Run: `chmod +x godot/tests/run_tests.sh && bash godot/tests/run_tests.sh; echo "exit=$?"`
Expected: `FAIL test_parse: found scripts to check` (until Task 3 adds code); `exit=1`. This proves the harness runs and detects problems.

- [ ] **Step 5: Commit**

```bash
git add godot/tests/
git commit -m "test(godot): headless test harness for the LTS port and overlay"
```

---

### Task 2: Vendor the MQTT addon

**Files:**
- Create: `godot/addons/godot-mqtt/` (vendored)
- Create: `godot/addons/godot-mqtt/LICENSE`
- Create: `godot/addons/godot-mqtt/` (vendored script library; not an editor plugin)

**Interfaces:**
- Consumes: nothing.
- Produces: global classes `MQTTClient` (and `MQTTPacket`/`MQTTClient` from the addon) available to `godot/src/mqtt_bridge.gd`.

- [ ] **Step 1: Fetch the pinned addon**

```bash
mkdir -p godot/addons/godot-mqtt
git clone https://github.com/goatchurchprime/godot-mqtt /tmp/opencode/godot-mqtt
cd /tmp/opencode/godot-mqtt && PIN=$(git rev-parse HEAD) && echo "PIN=$PIN"
cp -r /tmp/opencode/godot-mqtt/addons/godot-mqtt/. godot/addons/godot-mqtt/
```

- [ ] **Step 2: Record the pin and license**

```bash
printf 'goatchurchprime/godot-mqtt @ %s (MIT)\n' "$PIN" > godot/addons/godot-mqtt/PINNED.txt
test -f godot/addons/godot-mqtt/LICENSE || cp /tmp/opencode/godot-mqtt/LICENSE godot/addons/godot-mqtt/LICENSE 2>/dev/null || true
```

- [ ] **Step 3: Verify the vendored script**

The upstream addon has no `plugin.cfg` and is loaded as a script library, so do not register it as an editor plugin. `MQTTClient` is exposed through `class_name` in `mqtt.gd`.

- [ ] **Step 4: Verify it imports and the client class resolves**

Add to `godot/tests/test_parse.gd` a one-off check, or run:

```bash
"$GODOT" --headless --path godot --import 2>&1 | grep -i "godot-mqtt" && echo "addon imported"
"$GODOT" --headless --path godot --script res://tests/test_parse.gd
```
Expected: no parse errors from `res://addons/godot-mqtt/**`; `PASS test_parse`.

- [ ] **Step 5: Commit**

```bash
git add godot/addons/godot-mqtt
git commit -m "chore(godot): vendor pinned godot-mqtt addon (MIT)"
```

---

### Task 3: Import the LTS core subset + provenance log + ignore rules

**Files:**
- Create: `godot/Data/**` (copied/ported source subset)
- Create: `docs/porting/lts-port.md`
- Create: `godot/LICENSE`, `godot/CREDITS.md`
- Create: `godot/.gitignore`

**Interfaces:**
- Consumes: Libre-TrainSim source at `Libre-TrainSim-master/src/`.
- Produces: `res://Data/Scripts/{Math,Root,input_helper,chunk}.gd`, `.../{Rail,RailMap,Wagon,camera_base,chunk_manager,Signal,World,WorldObject}.gd`, and the required `Data/Modules/` files. Heavy `Resources/` dependencies must be optional or replaced by procedural fallbacks.

- [ ] **Step 1: Copy the core subset (no editor/modding/translations/caches)**

```bash
SRC=Libre-TrainSim-master/src
DST=godot
mkdir -p "$DST"
cp -r "$SRC/Data" "$DST/"
# Do not copy the full upstream Resources tree (~600MB). Keep only selected,
# redistributable text resources required by the runtime; use procedural
# fallbacks for absent binary assets.
cp "$SRC/LICENSE" "$DST/LICENSE" 2>/dev/null || cp Libre-TrainSim-master/LICENSE "$DST/LICENSE"
# strip non-source cruft
find "$DST" -name '.godot' -type d -prune -exec rm -rf {} +
find "$DST" \( -name '*.uid' -o -name '*.import' -o -name '*:Zone.Identifier' \) -delete
find "$DST/Data" -type d \( -name 'Editor' -o -name 'Translations' -o -name 'addons' -o -name 'Screens' \) -prune -exec rm -rf {} +
```

- [ ] **Step 2: Add Godot-side ignore rules**

`godot/.gitignore`:

```gitignore
.godot/
*.uid
*.import
*:Zone.Identifier
config.cfg
Resources/
```

- [ ] **Step 3: Write the license + credits**

`godot/LICENSE`: the full **GPL v3** text (from `Libre-TrainSim-master/LICENSE`).
`godot/CREDITS.md`:

```markdown
# Credits
- Core rail/train runtime ported from Libre-TrainSim (GPL v3), v0.9.beta1.
- MQTT client: goatchurchprime/godot-mqtt (MIT).
```

- [ ] **Step 4: Write the provenance log**

`docs/porting/lts-port.md`: a table with columns `File | Change | Reason | Godot-3 symbol`. Seed it with the entries produced in Tasks 4–7.

- [ ] **Step 5: Verify what still fails**

Run: `"$GODOT" --headless --path godot --script res://tests/test_parse.gd 2>&1 | tee /tmp/opencode/parse1.log`
Expected: FAIL with the remaining parse errors listed (baseline for Tasks 4–7). Record the list in `docs/porting/lts-port.md`.

- [ ] **Step 6: Commit**

```bash
git add godot/Data godot/.gitignore godot/LICENSE godot/CREDITS.md docs/porting/
git commit -m "feat(godot): import Libre-TrainSim core subset + GPL/credits/provenance"
```

---

### Task 4: Port the `Math` singleton (autoload)

**Files:**
- Modify: `godot/Data/Scripts/Singletons/Math.gd`
- Modify: `docs/porting/lts-port.md`

**Interfaces:**
- Consumes: nothing.
- Produces: autoload `Math` with `get_next_pos(radius, pos, world_rot, distance) -> Vector3` and `sort_signals(signal_table, forward) -> Array`.

- [ ] **Step 1: Reproduce the failure**

Run: `"$GODOT" --headless --path godot --script res://tests/test_parse.gd`
Expected: errors of the form `No constructor of "String" matches the signature "String(int)"` and `Function "invert()" not found in base Array` pointing at `Singletons/Math.gd`.

- [ ] **Step 2: Apply the Godot-4 fixes**

In `Math.gd`, replace every `String(<expr>)` with `str(<expr>)`, use
`Array.reverse()` instead of `Array.invert()`, and use `Array.remove_at(index)`
instead of the removed `Array.remove(index)`:

```gdscript
func time_to_string(time: Array) -> String:
	var hour = str(time[0])
	var minute = str(time[1])
	var second = str(time[2])
	...
func distance_to_string(distance: float) -> String:
	if distance > 10000:
		return str(int(distance/1000)) + " km"
	...
	if forward:
		return export_t
	else:
		export_t.reverse()
		return export_t
```

- [ ] **Step 3: Verify**

Run: `"$GODOT" --headless --path godot --script res://tests/test_parse.gd`
Expected: no `Math.gd` errors remaining (PASS may still fail on other files — that is fine for this task).

- [ ] **Step 4: Log + commit**

Add a `Math.gd` row to `docs/porting/lts-port.md`.

```bash
git add godot/Data/Scripts/Singletons/Math.gd docs/porting/lts-port.md
git commit -m "port(godot): Math singleton to Godot 4 (String()->str, invert()->reverse)"
```

---

### Task 5: Port the `Root` singleton (autoload)

**Files:**
- Modify: `godot/Data/Scripts/Singletons/Root.gd`
- Modify: `docs/porting/lts-port.md`

**Interfaces:**
- Consumes: nothing.
- Produces: autoload `Root` with `crawl_directory(found_files, directory_path, file_extensions, recursion_depth) -> void` and signal `world_origin_shifted(delta)`.

- [ ] **Step 1: Reproduce**

Run: `"$GODOT" --headless --path godot --script res://tests/test_parse.gd`
Expected: `Native class "DirAccess" cannot be constructed`, `Name "new" is a Callable`, `Function "plus_file()" not found`, and `Function "world_origin_shifted" has the same name as a previously declared signal`.

- [ ] **Step 2: Fix `DirAccess` construction + iteration**

Replace each `var dir := DirAccess.new()` + `dir.open(path)` with `var dir := DirAccess.open(path)` and every `dir.list_dir_begin()` with `dir.list_dir_begin()` (Godot 4 signature, no args). Example (`crawl_directory`):

```gdscript
func crawl_directory(found_files: Array, directory_path: String, file_extensions: Array, recursion_depth: int = -1) -> void:
	var dir := DirAccess.open(directory_path)
	if dir == null or dir.list_dir_begin() != OK:
		return
	while true:
		var file := dir.get_next()
		if file.is_empty():
			break
		elif dir.current_is_dir() and recursion_depth != 0:
			crawl_directory(found_files, directory_path.path_join(file), file_extensions, recursion_depth - 1)
		else:
			var ext := file.get_extension()
			if OS.has_feature("standalone") and ext == "import":
				file = file.get_basename()
				ext = file.get_extension()
			if ext in file_extensions:
				found_files.push_back(directory_path.path_join(file))
	dir.list_dir_end()
```

- [ ] **Step 3: Fix the signal/function name clash**

Rename the function to an emitter helper and keep the signal:

```gdscript
func emit_world_origin_shifted(delta) -> void:
	world_origin_shifted.emit(delta)
```
Then update callers (grep for `world_origin_shifted(` and `.connect(`):

```bash
grep -rn "world_origin_shifted" godot/Data
```
Replace `Root.connect("world_origin_shifted", Callable(self, "_on_world_origin_shifted"))` with `Root.world_origin_shifted.connect(_on_world_origin_shifted)`.

- [ ] **Step 4: Fix remaining `plus_file` in `Root.gd`**

Replace `.plus_file(` with `.path_join(` throughout `Root.gd`.

- [ ] **Step 5: Verify + log + commit**

Run: `"$GODOT" --headless --path godot --script res://tests/test_parse.gd` — expect no `Root.gd` errors.

```bash
git add godot/Data/Scripts/Singletons/Root.gd docs/porting/lts-port.md
git commit -m "port(godot): Root singleton to Godot 4 (DirAccess.open, path_join, signal rename)"
```

---

### Task 6: Port `input_helper.gd` (Godot-3 joystick constants)

**Files:**
- Modify: `godot/Data/Scripts/Singletons/input_helper.gd`
- Modify: `docs/porting/lts-port.md`

**Interfaces:**
- Consumes: `ControlType` enum (from `Data/Scripts/Enums`).
- Produces: unchanged public API `make_strings_from_actions(actions) -> Array`.

- [ ] **Step 1: Reproduce**

Run: `"$GODOT" --headless --path godot --script res://tests/test_parse.gd`
Expected: `Identifier "JOY_XBOX_A" not declared`, `JOY_L3`, `JOY_DPAD_UP`, `JOY_ANALOG_LX`, etc.

- [ ] **Step 2: Remap the constants to Godot 4**

Apply this mapping in `input_helper.gd` (and anywhere else the identifiers appear):

| Godot 3 | Godot 4 |
|---|---|
| `JOY_XBOX_A` | `JOY_BUTTON_A` |
| `JOY_XBOX_B` | `JOY_BUTTON_B` |
| `JOY_XBOX_X` | `JOY_BUTTON_X` |
| `JOY_XBOX_Y` | `JOY_BUTTON_Y` |
| `JOY_SONY_X/CIRCLE/SQUARE/TRIANGLE` | `JOY_BUTTON_A/B/X/Y` |
| `JOY_L`/`JOY_R` | `JOY_BUTTON_LEFT_SHOULDER`/`JOY_BUTTON_RIGHT_SHOULDER` |
| `JOY_L2`/`JOY_R2` | These are axes in Godot 4; map them to `JOY_AXIS_TRIGGER_LEFT`/`JOY_AXIS_TRIGGER_RIGHT` in axis-label helpers, not in button matchers |
| `JOY_SELECT`/`JOY_START` | `JOY_BUTTON_BACK`/`JOY_BUTTON_START` |
| `JOY_L3`/`JOY_R3` | `JOY_BUTTON_LEFT_STICK`/`JOY_BUTTON_RIGHT_STICK` |
| `JOY_DPAD_*` | `JOY_BUTTON_DPAD_*` |
| `JOY_ANALOG_LX/LY/RX/RY` | `JOY_AXIS_LEFT_X/LEFT_Y/RIGHT_X/RIGHT_Y` |
| `JOY_ANALOG_L2/R2` | `JOY_AXIS_TRIGGER_LEFT/RIGHT` |

- [ ] **Step 3: Verify + log + commit**

Run: `"$GODOT" --headless --path godot --script res://tests/test_parse.gd` — expect no `input_helper.gd` errors.

```bash
git add godot/Data/Scripts/Singletons/input_helper.gd docs/porting/lts-port.md
git commit -m "port(godot): input_helper joystick constants to Godot 4"
```

---

### Task 7: Port `chunk.gd` + convert required scenes to `format=3`

**Files:**
- Modify: `godot/Data/Scripts/chunk.gd`
- Modify: required `*.tscn` under `godot/Data/Modules/`
- Modify: `docs/porting/lts-port.md`

**Interfaces:**
- Consumes: `ChunkManager`.
- Produces: `Chunk` (`class_name Chunk extends Node3D`) with `update()`, `_on_world_origin_shifted(delta)`.

- [ ] **Step 1: Reproduce**

Run: `"$GODOT" --headless --path godot --script res://tests/test_parse.gd`
Expected: `Failed to load script ".../chunk.gd" with error "Parse error"`.

- [ ] **Step 2: Fix `chunk.gd` Godot-4 issues**

```gdscript
# Godot 4 connect syntax
Root.world_origin_shifted.connect(_on_world_origin_shifted)
# typed export array
@export var rails: Array[String] = []
# instantiate() already used (Godot 4) — keep
```

- [ ] **Step 3: Convert the scenes the core needs from `format=2` to `format=3`**

Open the project once in the Godot 4.7 **editor on Windows** (or run the headless upgrade on a scratch copy) to let Godot convert `Data/Modules/chunk_prefab.tscn`, `chunk_prefab_default_grass.tscn`, `Rail.tscn`, `Signal.tscn`, and `World-Pattern.tscn`. Confirm conversion:

```bash
grep -l 'format=3' godot/Data/Modules/*.tscn
```
Expected: the five files listed above now start with `format=3`.

- [ ] **Step 4: Verify**

Run: `"$GODOT" --headless --path godot --script res://tests/test_parse.gd`
Expected: `PASS test_parse` for the selected runtime and overlay scripts. Excluded legacy/editor/UI scripts and ignored binary assets must not be loaded by this smoke test.

- [ ] **Step 5: Commit**

```bash
git add godot/Data/Scripts/chunk.gd godot/Data/Modules docs/porting/lts-port.md
git commit -m "port(godot): chunk.gd + convert core scenes to Godot 4 format"
```

---

### Task 8: Minimal rail + train scene loads headless

**Files:**
- Create: `godot/scenes/minimal_railway.tscn`
- Modify: `godot/main.tscn`, `godot/main.gd`
- Create: `godot/tests/test_scene_load.gd`

**Interfaces:**
- Consumes: `Rail`, `Wagon`, `Math`.
- Produces: `main.tscn` instantiating `LTSTrain` (a `Wagon` with a `speed_kmh` accessor) on a rail; scene exports `func set_target_speed_kmh(v: float)` / `func get_speed_kmh() -> float`.

- [ ] **Step 1: Add the train API shim**

Create `godot/src/ltstrain.gd`:

```gdscript
class_name LTSTrain
extends Wagon

var _target_speed_kmh: float = 0.0

func set_target_speed_kmh(v: float) -> void:
	_target_speed_kmh = clampf(v, 0.0, 160.0)

func get_target_speed_kmh() -> float:
	return _target_speed_kmh

func get_speed_kmh() -> float:
	return Math.speed_to_kmh(speed)

func get_track_position_m() -> float:
	return distance_on_route
```

- [ ] **Step 2: Build the minimal scene**

`godot/scenes/minimal_railway.tscn`: one `Rail` (radius 0, length 500, straight) + one `LTSTrain` node at the rail start. Point `main.tscn` at `main.gd`, and in `main.gd` `_ready()` instance `minimal_railway.tscn`.

- [ ] **Step 3: Write the load test**

`godot/tests/test_scene_load.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var a := Assert.new()
	var packed: PackedScene = load("res://scenes/minimal_railway.tscn")
	a.ok(packed != null, "scene loads")
	var inst = packed.instantiate()
	get_root().add_child(inst)
	a.ok(inst.find_child("Train", true, false) != null, "train present")
	quit(a.report("test_scene_load"))
```

- [ ] **Step 4: Run**

Run: `bash godot/tests/run_tests.sh; echo "exit=$?"`
Expected: `PASS test_parse`, `PASS test_scene_load`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add godot/src/ltstrain.gd godot/scenes/ godot/main.tscn godot/main.gd godot/tests/test_scene_load.gd
git commit -m "feat(godot): minimal rail+train scene loads headless"
```

---

### Task 9: MQTT bridge with reconnect/backoff

**Files:**
- Create: `godot/src/mqtt_bridge.gd`
- Create: `godot/tests/test_mqtt_bridge.gd`
- Modify: `godot/config.cfg.sample`

**Interfaces:**
- Consumes: `MQTTClient` (addon).
- Produces: `MQTTBridge` node: `func connect_broker()`, `func publish(topic: String, payload: Dictionary)`, signal `message(topic: String, payload: Dictionary)`, signal `connected()`, `disconnected()`.

- [ ] **Step 1: Write the bridge**

`godot/src/mqtt_bridge.gd` (core):

```gdscript
class_name MQTTBridge
extends Node

signal connected
signal disconnected
signal message(topic: String, payload: Dictionary)

@export var host := "127.0.0.1"
@export var port := 1883
@export var username := "godot"
@export var password := "godot-dev-pass"
@export var subscriptions: Array[String] = []

var _client: MQTTClient
var _backoff := 1.0
var _connected := false

func _ready() -> void:
	_try_connect()

func _try_connect() -> void:
	_client = MQTTClient.new()
	add_child(_client)
	_client.connect(_client.connection_established, _on_established)
	_client.connect(_client.connection_closed, _on_closed)
	_client.connect(_client.message_received, _on_message)
	_client.connect_to_broker(host, port, {"username": username, "password": password})

func _on_established() -> void:
	_connected = true
	_backoff = 1.0
	for t in subscriptions:
		_client.subscribe(t)
	connected.emit()

func _on_closed() -> void:
	_connected = false
	disconnected.emit()
	if is_inside_tree():
		await get_tree().create_timer(_backoff).timeout
		_backoff = minf(_backoff * 2.0, 30.0)
		_try_connect()

func _on_message(topic: String, payload: PackedByteArray) -> void:
	var parsed = JSON.parse_string(payload.get_string_from_utf8())
	if typeof(parsed) == TYPE_DICTIONARY:
		message.emit(topic, parsed)

func publish(topic: String, payload: Dictionary) -> void:
	if _connected:
		_client.publish(topic, JSON.stringify(payload))
```

- [ ] **Step 2: Add sample config keys**

Append to `godot/config.cfg.sample`:

```ini
[mqtt]
host=127.0.0.1
port=1883
username=godot
password=godot-dev-pass
```

- [ ] **Step 3: Write the integration test**

`godot/tests/test_mqtt_bridge.gd` (requires `docker compose up -d mosquitto`):

```gdscript
extends SceneTree

var _got := false

func _initialize() -> void:
	var a := Assert.new()
	var bridge := MQTTBridge.new()
	bridge.host = "127.0.0.1"
	bridge.subscriptions = ["railway/test/echo"]
	bridge.message.connect(func(topic, payload): _got = true)
	get_root().add_child(bridge)
	await create_timer(1.5).timeout
	bridge.publish("railway/test/echo", {"hello": "world"})
	await create_timer(1.5).timeout
	a.ok(_got, "received own published message")
	quit(a.report("test_mqtt_bridge"))
```

- [ ] **Step 4: Run**

```bash
docker compose up -d mosquitto
bash godot/tests/run_tests.sh; echo "exit=$?"
```
Expected: `PASS test_mqtt_bridge`, `exit=0`. (If the broker rejects the anonymous/echo topic, adjust `mosquitto/acl_file` **only after coordinating** — it is a shared file.)

- [ ] **Step 5: Commit**

```bash
git add godot/src/mqtt_bridge.gd godot/tests/test_mqtt_bridge.gd godot/config.cfg.sample
git commit -m "feat(godot): MQTT bridge with exponential-backoff reconnect"
```

---

### Task 10: Motion reconciliation (train controller)

**Files:**
- Create: `godot/src/train_controller.gd`
- Create: `godot/tests/test_train_controller.gd`

**Interfaces:**
- Consumes: `LTSTrain` (`set_target_speed_kmh`, `get_target_speed_kmh`), `twin_state.gd`.
- Produces: `TrainController.apply_safety(zone_state: Dictionary, train: LTSTrain) -> void`; `TrainController.zone_limit_kmh(zone_state) -> float`.

- [ ] **Step 1: Write the controller**

`godot/src/train_controller.gd`:

```gdscript
class_name TrainController
extends RefCounted

const CAUTION_KMH := 30.0

func zone_limit_kmh(zone_state: Dictionary) -> float:
	match String(zone_state.get("state", "clear")):
		"clear": return float(zone_state.get("speedLimitKmh", 80.0))
		"warn": return CAUTION_KMH
		"hazard", "sensor_fault": return 0.0
		_: return CAUTION_KMH

func apply_safety(zone_state: Dictionary, train: LTSTrain) -> void:
	train.set_target_speed_kmh(zone_limit_kmh(zone_state))
```

- [ ] **Step 2: Write the test**

`godot/tests/test_train_controller.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var a := Assert.new()
	var c := TrainController.new()
	var train := load("res://src/ltstrain.gd").new()
	c.apply_safety({"state": "clear", "speedLimitKmh": 80}, train)
	a.eq(train.get_target_speed_kmh(), 80.0, "clear -> zone limit")
	c.apply_safety({"state": "warn"}, train)
	a.eq(train.get_target_speed_kmh(), 30.0, "warn -> caution")
	c.apply_safety({"state": "hazard"}, train)
	a.eq(train.get_target_speed_kmh(), 0.0, "hazard -> stop")
	c.apply_safety({"state": "clear", "speedLimitKmh": 80}, train)
	a.eq(train.get_target_speed_kmh(), 80.0, "clear -> resume")
	quit(a.report("test_train_controller"))
```

- [ ] **Step 3: Run**

Run: `bash godot/tests/run_tests.sh; echo "exit=$?"`
Expected: `PASS test_train_controller`, `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add godot/src/train_controller.gd godot/tests/test_train_controller.gd
git commit -m "feat(godot): graduated motion reconciliation (warn/slow/stop/resume)"
```

---

### Task 11: Wildlife observation publisher

**Files:**
- Create: `godot/src/wildlife_publisher.gd`
- Create: `godot/tests/test_wildlife_publisher.gd`

**Interfaces:**
- Consumes: `MQTTBridge.publish`.
- Produces: `WildlifePublisher.report(zone: String, species: String, count: int, on_track: bool) -> void`; publishes retained=False `railway/zoneN/wildlife` on change only (debounced).

- [ ] **Step 1: Write the publisher**

`godot/src/wildlife_publisher.gd`:

```gdscript
class_name WildlifePublisher
extends Node

@export var bridge: MQTTBridge
@export var zone := "zone1"

var _last := ""

func report(species: String, count: int, on_track: bool) -> void:
	var payload := {
		"zone": zone,
		"wildlifeDetected": count > 0,
		"species": species,
		"count": count,
		"timestamp": Time.get_unix_time_from_system(),
	}
	var key := JSON.stringify(payload)
	if key == _last:
		return
	_last = key
	if bridge:
		bridge.publish("railway/%s/wildlife" % zone, payload)
```

- [ ] **Step 2: Write the test**

`godot/tests/test_wildlife_publisher.gd`:

```gdscript
extends SceneTree

class FakeBridge extends MQTTBridge:
	var topic := ""
	var payload := {}
	func publish(t: String, p: Dictionary) -> void:
		topic = t; payload = p

func _initialize() -> void:
	var a := Assert.new()
	var fb := FakeBridge.new()
	var pub := WildlifePublisher.new()
	pub.bridge = fb
	pub.zone = "zone1"
	pub.report("deer", 1, true)
	a.eq(fb.topic, "railway/zone1/wildlife", "topic")
	a.eq(fb.payload["count"], 1, "count")
	a.eq(fb.payload["wildlifeDetected"], true, "detected")
	pub._last = ""
	quit(a.report("test_wildlife_publisher"))
```

- [ ] **Step 3: Run + commit**

Run: `bash godot/tests/run_tests.sh; echo "exit=$?"` — expect all PASS, `exit=0`.

```bash
git add godot/src/wildlife_publisher.gd godot/tests/test_wildlife_publisher.gd
git commit -m "feat(godot): wildlife observation publisher (debounced)"
```

---

## Self-Review

- **Spec coverage:** §3 port → Tasks 3–7; §4 architecture → Tasks 3, 8, 10; §5 MQTT contract → Tasks 9, 11; §6 reconciliation → Task 10; §13 config → Tasks 9; §15 automated headless gate → Task 1 harness used throughout. World/wildlife visuals/cameras (§7, §8, §10) and D/E (§11, §12) are covered by the other three plans.
- **Placeholder scan:** no TBD/"handle errors" steps; every code step shows code. The joystick remap is a full table (acceptable as a mechanical mapping with the exact identifiers).
- **Type consistency:** `set_target_speed_kmh`/`get_speed_kmh`/`get_track_position_m` defined in Task 8 and used by Task 10; `MQTTBridge.publish` defined Task 9 and used Task 11; `WildlifePublisher.report` defined Task 11.
