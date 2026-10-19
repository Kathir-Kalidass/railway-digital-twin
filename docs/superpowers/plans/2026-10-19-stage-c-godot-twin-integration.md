# Stage C1 — Godot Twin Integration & Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Godot prototype's unauthenticated HTTP path with an authenticated MQTT client and render the Stage A2 authoritative multi-train, block-signalling state on a double-track scene, correctly and verifiably.

**Architecture:** Vendor the MIT `goatchurchprime/godot-mqtt` addon (pure GDScript) and wrap it in `mqtt_bridge.gd` (connect/auth/validate/publish/reconnect). `twin_state.gd` holds the validated authoritative snapshot. Scene builders (`track_builder`, `signal_renderer`, `train_controller`, `crossing_controller`, `camera_director`, `hud`) consume typed state and never publish. Visual/animation/asset enrichment is a separate follow-on plan (C2); this plan targets **Forward+ with asset-optional procedural placeholders** so it is fully testable headlessly.

**Tech Stack:** Godot 4.7 (installed at `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64`), GDScript, `goatchurchprime/godot-mqtt` (MIT), MQTT 3.1.1 over plaintext TCP.

**Spec:** [`../specs/2026-10-19-stage-c-godot-digital-twin-design.md`](../specs/2026-10-19-stage-c-godot-digital-twin-design.md)

## Global Constraints

- Godot version: **4.7** (`config/features=PackedStringArray("4.7")`).
- Godot must **never** publish `railway/state`, `railway/events`, `railway/alerts`, `railway/commands/*`, `railway/signal/*`, `railway/zoneN/signal`, or `railway/zoneN/train`.
- Godot's only MQTT write is `railway/zoneN/wildlife`. Godot must not call any REST control endpoint.
- Renderer: `Forward+` primary; a `gl_compatibility` fallback preset must remain selectable.
- Speeds clamp to `0..80`; braking uses illustrative `1.2 m/s²` display estimate unless overridden by config.
- Headless correctness must hold with **no external assets present**.
- Config `godot/config.cfg` is ignored; `config.cfg.sample` uses placeholders only — never credentials in git.
- Logs must never include the MQTT password.
- Zone ids are exactly `zone1`,`zone2`.

## File Structure

- Modify `godot/project.godot` — renderer, quality preset autoload-free settings, input map.
- Modify `godot/config.cfg.sample` — `[mqtt]`/`[simulation]` sections; drop `[network]`.
- Create `godot/addons/mqtt/` (vendored addon), `godot/addons/mqtt/VENDOR.md`.
- Create `godot/scripts/mqtt_bridge.gd`, `twin_state.gd`, `world_builder.gd`, `track_builder.gd`, `train_controller.gd`, `wildlife_controller.gd`, `signal_renderer.gd`, `crossing_controller.gd`, `camera_director.gd`, `hud.gd`.
- Rewrite `godot/main.gd` as composition root.
- Create `godot/tests/run_headless.gd`, `godot/tests/test_twin_state.gd`, `godot/tests/test_mqtt_bridge.gd`.
- Create `godot/assets/CREDITS.md` (placeholder manifest; assets land in C2).

---

### Task 1: Project settings, renderer, and config sample

**Files:**
- Modify: `godot/project.godot`
- Modify: `godot/config.cfg.sample`
- Test: `godot/tests/run_headless.gd`

**Interfaces:**
- Produces: renderer `forward_plus`; input actions `toggle_wildlife_1`, `toggle_wildlife_2`, `cycle_camera`, `cycle_weather`, `toggle_daynight`, `play_scenario`.
- Produces: `AppConfig` parsing `[mqtt]` and `[simulation]`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/run_headless.gd`:

```gdscript
extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var cfg := ConfigFile.new()
	cfg.set_value("mqtt", "host", "127.0.0.1")
	cfg.set_value("mqtt", "port", 1883)
	cfg.set_value("mqtt", "username", "godot")
	cfg.set_value("mqtt", "password", "x")
	cfg.set_value("mqtt", "client_id_prefix", "godot-twin")
	cfg.set_value("simulation", "zones", ["zone1", "zone2"])
	cfg.set_value("simulation", "quality", "high")
	var parsed := AppConfig.from_config(cfg)
	if parsed.mqtt_port != 1883: failures.append("mqtt_port")
	if parsed.zones != ["zone1", "zone2"]: failures.append("zones")
	if parsed.renderer_quality != "high": failures.append("quality")
	if OS.has_feature("headless") == false: failures.append("not headless")
	if failures.is_empty():
		print("PASS run_headless")
	else:
		printerr("FAIL run_headless: %s" % ", ".join(failures))
	quit(0 if failures.is_empty() else 1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/run_headless.gd`
Expected: FAIL — `AppConfig` not found.

- [ ] **Step 3: Add `AppConfig` to `mqtt_bridge.gd`'s sibling `twin_state.gd`**

Add at the top of `godot/scripts/twin_state.gd` (created in Task 3; create the file now with just this class if running this task first):

```gdscript
class_name AppConfig
extends RefCounted

var mqtt_host: String = "127.0.0.1"
var mqtt_port: int = 1883
var mqtt_username: String = "godot"
var mqtt_password: String = ""
var client_id_prefix: String = "godot-twin"
var zones: Array = ["zone1", "zone2"]
var renderer_quality: String = "high"
var max_publish_hz: float = 2.0

static func from_config(cfg: ConfigFile) -> AppConfig:
	var c := AppConfig.new()
	c.mqtt_host = str(cfg.get_value("mqtt", "host", "127.0.0.1"))
	c.mqtt_port = int(cfg.get_value("mqtt", "port", 1883))
	c.mqtt_username = str(cfg.get_value("mqtt", "username", "godot"))
	c.mqtt_password = str(cfg.get_value("mqtt", "password", ""))
	c.client_id_prefix = str(cfg.get_value("mqtt", "client_id_prefix", "godot-twin"))
	c.zones = cfg.get_value("simulation", "zones", ["zone1", "zone2"])
	c.renderer_quality = str(cfg.get_value("simulation", "quality", "high"))
	c.max_publish_hz = float(cfg.get_value("simulation", "max_publish_hz", 2.0))
	return c

static func load_default() -> AppConfig:
	var cfg := ConfigFile.new()
	if cfg.load("res://config.cfg") == OK:
		return AppConfig.from_config(cfg)
	return AppConfig.new()
```

- [ ] **Step 4: Update `project.godot`**

Set renderer to Forward+, keep mobile fallback, add the input actions:

```ini
[rendering]

renderer/rendering_method="forward_plus"
renderer/rendering_method.mobile="gl_compatibility"
anti_aliasing/quality/msaa_3d=2
environment/defaults/default_clear_color=Color(0.07, 0.13, 0.16, 1)

[input]

toggle_wildlife_1={"deadzone":0.5,"events":[{"type":"key","keycode":32}]}
toggle_wildlife_2={"deadzone":0.5,"events":[{"type":"key","keycode":50}]}
cycle_camera={"deadzone":0.5,"events":[{"type":"key","keycode":67}]}
cycle_weather={"deadzone":0.5,"events":[{"type":"key","keycode":87}]}
toggle_daynight={"deadzone":0.5,"events":[{"type":"key","keycode":78}]}
play_scenario={"deadzone":0.5,"events":[{"type":"key","keycode":80}]}
```

- [ ] **Step 5: Replace `config.cfg.sample`**

```ini
[mqtt]
host="127.0.0.1"
port=1883
username="godot"
password="change-me"
client_id_prefix="godot-twin"

[simulation]
zones=["zone1","zone2"]
quality="high"
max_publish_hz=2.0
day_night="day"
weather="clear"
scenario=""
```

- [ ] **Step 6: Run test, expect pass**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/run_headless.gd`
Expected: `PASS run_headless`.

- [ ] **Step 7: Commit**

```bash
git add godot/project.godot godot/config.cfg.sample godot/scripts/twin_state.gd godot/tests/run_headless.gd
git commit -m "feat(godot): forward+ renderer, input map, and mqtt config"
```

---

### Task 2: Vendor the MQTT addon

**Files:**
- Create: `godot/addons/mqtt/**`, `godot/addons/mqtt/VENDOR.md`
- Test: headless load

**Interfaces:**
- Produces: a working addon exposing `MQTTClient` (connect, subscribe, publish, signals `broker_connected`, `broker_disconnected`, `broker_connection_failed`, `message_received`).

- [ ] **Step 1: Vendor the addon**

Run:

```bash
tmp=$(mktemp -d)
git clone --depth 1 https://github.com/goatchurchprime/godot-mqtt "$tmp/godot-mqtt"
mkdir -p godot/addons/mqtt
cp -r "$tmp/godot-mqtt/addons/mqtt/." godot/addons/mqtt/
cp "$tmp/godot-mqtt/LICENSE" godot/addons/mqtt/LICENSE
git -C "$tmp/godot-mqtt" rev-parse HEAD
```

Record the printed commit hash. If the addon path differs in the upstream repo, copy the directory containing `mqtt.gd`.

- [ ] **Step 2: Write `godot/addons/mqtt/VENDOR.md`**

```markdown
# Vendored MQTT addon

- Project: goatchurchprime/godot-mqtt
- Source: https://github.com/goatchurchprime/godot-mqtt
- Commit: <PASTE THE HASH PRINTED ABOVE>
- License: MIT (see ./LICENSE)
- Vendored for offline builds; do not edit upstream files in place.
- Gap handled downstream: no built-in reconnect — implemented in
  `res://scripts/mqtt_bridge.gd`.
```

- [ ] **Step 3: Verify the project still loads headlessly**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path godot --quit 2>&1 | grep -iE "error|script"` 
Expected: no script/resource errors mentioning the addon.

- [ ] **Step 4: Commit**

```bash
git add godot/addons/mqtt
git commit -m "chore(godot): vendor goatchurchprime/godot-mqtt (MIT)"
```

---

### Task 3: `twin_state.gd` — validated authoritative snapshot

**Files:**
- Modify: `godot/scripts/twin_state.gd`
- Create: `godot/tests/test_twin_state.gd`
- Modify: `godot/tests/run_headless.gd`

**Interfaces:**
- Produces: `TwinState` with `apply_snapshot(parsed: Dictionary) -> bool`, `apply_block_signal(block: String, signal: String) -> bool`, `is_synced() -> bool`, `is_stale(now_ms: int, max_age_ms: int) -> bool`, `status_text() -> String`, plus accessors `zones`, `trains`, `blocks`, `lines`, `station`, `updated_at_ms`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/test_twin_state.gd`:

```gdscript
class_name TestTwinState
extends RefCounted

static func run() -> Array:
	var failures: Array[String] = []
	var t := TwinState.new()
	# malformed rejected
	if t.apply_snapshot({}) != false: failures.append("reject empty")
	# missing zones rejected
	if t.apply_snapshot({"zones": {}, "trains": [], "blocks": [], "updatedAt": "2026-01-01T00:00:00.000Z"}) != false:
		failures.append("reject no zones")
	var ok := {
		"zones": {"zone1": {"signal": "GREEN"}, "zone2": {"signal": "YELLOW"}},
		"trains": [{"id": "T1", "block": "UP-B0", "offsetM": 10.0, "speedKmh": 40.0}],
		"blocks": [{"id": "UP-B0", "line": "UP", "zone": "zone1", "occupiedBy": "T1"}],
		"lines": [{"id": "UP", "blocks": ["UP-B0"]}],
		"station": {"id": "station", "blocks": {"UP": "UP-B0"}},
		"updatedAt": "2026-01-01T00:00:00.000Z",
	}
	if t.apply_snapshot(ok) != true: failures.append("accept valid")
	if not t.is_synced(): failures.append("synced")
	if t.trains.size() != 1: failures.append("trains")
	if t.zones["zone2"]["signal"] != "YELLOW": failures.append("zone signal")
	# invalid block signal ignored
	if t.apply_block_signal("UP-B0", "PURPLE") != false: failures.append("reject bad aspect")
	if t.apply_block_signal("UP-B0", "RED") != true: failures.append("accept aspect")
	return failures
```

Append to `godot/tests/run_headless.gd` before the final `quit`:

```gdscript
	failures.append_array(TestTwinState.run())
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/run_headless.gd`
Expected: FAIL (`TwinState` not found).

- [ ] **Step 3: Implement `TwinState`**

Append to `godot/scripts/twin_state.gd`:

```gdscript
class_name TwinState
extends RefCounted

const ASPECTS := ["GREEN", "YELLOW", "RED"]
const MAX_AGE_MS := 15000

var zones: Dictionary = {}
var trains: Array = []
var blocks: Array = []
var lines: Array = []
var station: Dictionary = {}
var updated_at_ms: int = 0
var synced: bool = false

func _parse_iso_ms(s: String) -> int:
	var d := Time.get_datetime_dict_from_datetime_string(s, true)
	if d.is_empty():
		return 0
	return int(Time.get_unix_time_from_datetime_dict(d)) * 1000

func apply_snapshot(parsed: Dictionary) -> bool:
	if typeof(parsed) != TYPE_DICTIONARY: return false
	var z = parsed.get("zones")
	if typeof(z) != TYPE_DICTIONARY or z.size() == 0: return false
	var ts := str(parsed.get("updatedAt", ""))
	var ms := _parse_iso_ms(ts)
	if ms == 0: return false
	zones = z
	trains = parsed.get("trains", [])
	blocks = parsed.get("blocks", [])
	lines = parsed.get("lines", [])
	station = parsed.get("station", {})
	updated_at_ms = ms
	synced = true
	return true

func apply_block_signal(block: String, aspect: String) -> bool:
	if not ASPECTS.has(aspect): return false
	for b in blocks:
		if b.get("id", "") == block:
			b["signal"] = aspect
			return true
	return false

func is_synced() -> bool:
	return synced

func is_stale(now_ms: int, max_age_ms: int = MAX_AGE_MS) -> bool:
	return not synced or (now_ms - updated_at_ms) > max_age_ms

func status_text() -> String:
	return "LIVE" if synced else "SYNCING"
```

- [ ] **Step 4: Run test, expect pass**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/run_headless.gd`
Expected: `PASS run_headless`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/twin_state.gd godot/tests/test_twin_state.gd godot/tests/run_headless.gd
git commit -m "feat(godot): validated authoritative twin state"
```

---

### Task 4: `mqtt_bridge.gd` — connect, validate, publish, reconnect

**Files:**
- Create: `godot/scripts/mqtt_bridge.gd`
- Create: `godot/tests/test_mqtt_bridge.gd`

**Interfaces:**
- Produces: `MqttBridge extends Node` with `configure(cfg: AppConfig)`, `start()`, `stop()`, `publish_wildlife(zone: String, detected: bool)`, signals `snapshot_received(parsed: Dictionary)`, `block_signal(block: String, aspect: String)`, `status_changed(status: String)`.
- Consumes: vendored addon `MQTTClient`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/test_mqtt_bridge.gd`:

```gdscript
class_name TestMqttBridge
extends RefCounted

static func run() -> Array:
	var failures: Array[String] = []
	var b := MqttBridge.new()
	# topic routing/mapping without a broker
	var routed := b._route_topic("railway/state")
	if routed != "state": failures.append("route state")
	if b._route_topic("railway/signal/UP-B0") != "block": failures.append("route block")
	if b._route_topic("railway/zone1/signal") != "zone_signal": failures.append("route zone signal")
	if b._route_topic("railway/speed/zone1") != "speed": failures.append("route speed")
	if b._route_topic("railway/commands/zone1") != "command": failures.append("route command")
	if b._route_topic("railway/other") != "ignore": failures.append("route ignore")
	# zone extraction
	if b._zone_from_topic("railway/zone2/signal") != "zone2": failures.append("zone parse")
	b.free()
	return failures
```

Append its `run()` to `run_headless.gd`.

- [ ] **Step 2: Run to verify it fails**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/run_headless.gd`
Expected: FAIL (`MqttBridge` not found).

- [ ] **Step 3: Implement `mqtt_bridge.gd`**

Create `godot/scripts/mqtt_bridge.gd`:

```gdscript
class_name MqttBridge
extends Node

signal snapshot_received(parsed: Dictionary)
signal block_signal(block: String, aspect: String)
signal status_changed(status: String)

const TOPIC_STATE := "railway/state"
const MAX_BACKOFF_MS := 30000

var cfg: AppConfig
var _client = null
var _subs: PackedStringArray = PackedStringArray(["railway/state", "railway/signal/+", "railway/zone1/signal", "railway/zone2/signal", "railway/speed/zone1", "railway/speed/zone2", "railway/commands/zone1", "railway/commands/zone2"])
var _backoff_ms: int = 1000
var _running: bool = false
var _status: String = "SYNCING"

func configure(c: AppConfig) -> void:
	cfg = c

func start() -> void:
	if _running: return
	_running = true
	_connect()

func stop() -> void:
	_running = false
	if _client:
		_client.disconnect_from_broker()
		_client = null

func _set_status(s: String) -> void:
	_status = s
	status_changed.emit(s)

func _connect() -> void:
	if not _running: return
	_client = load("res://addons/mqtt/mqtt.gd").new() if false else MQTTClass.new() if false else _new_client()
	_client.set_user_pass(cfg.mqtt_username, cfg.mqtt_password)
	_client.connect_to_broker(cfg.mqtt_host, cfg.mqtt_port, {"client_id": "%s-%d" % [cfg.client_id_prefix, Time.get_ticks_usec()]})
	_client.on_broker_connected = func() -> void:
		_backoff_ms = 1000
		_set_status("SYNCING")
		_client.subscribe(_subs)
	_client.on_broker_disconnected = func() -> void:
		_set_status("OFFLINE")
		_schedule_reconnect()
	_client.on_broker_connection_failed = func() -> void:
		_set_status("OFFLINE")
		_schedule_reconnect()
	_client.on_message = func(topic: String, payload: PackedByteArray) -> void:
		_handle_message(topic, payload)

func _new_client():
	# Instantiate the vendored addon's client class by script.
	var script = load("res://addons/mqtt/mqtt.gd")
	return script.new()

func _schedule_reconnect() -> void:
	if not _running: return
	var delay := _backoff_ms
	_backoff_ms = min(MAX_BACKOFF_MS, _backoff_ms * 2)
	get_tree().create_timer(float(delay) / 1000.0).timeout.connect(func() -> void:
		if _running: _connect()
	)

func _route_topic(topic: String) -> String:
	if topic == TOPIC_STATE: return "state"
	if topic.begins_with("railway/signal/"): return "block"
	if topic.match("railway/zone*/signal"): return "zone_signal"
	if topic.match("railway/speed/zone*"): return "speed"
	if topic.match("railway/commands/zone*"): return "command"
	return "ignore"

func _zone_from_topic(topic: String) -> String:
	var parts := topic.split("/")
	for p in parts:
		if p.begins_with("zone"): return p
	return ""

func _handle_message(topic: String, payload: PackedByteArray) -> void:
	var text := payload.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Ignoring malformed MQTT payload on %s" % topic)
		return
	match _route_topic(topic):
		"state":
			_set_status("SYNCING")
			snapshot_received.emit(parsed)
		"block":
			var id := topic.substr("railway/signal/".length())
			block_signal.emit(id, str(parsed.get("signal", "")))
		"zone_signal", "speed", "command":
			pass
		_:
			push_warning("Ignoring unhandled topic %s" % topic)

func publish_wildlife(zone: String, detected: bool) -> bool:
	if _client == null or not _client.is_connected_to_broker(): return false
	var payload := {"wildlifeDetected": detected, "timestamp": Time.get_datetime_string_from_system(true, true) + "Z", "source": "godot"}
	_client.publish("railway/%s/wildlife" % zone, JSON.stringify(payload), 0, false)
	return true
```

Note: confirm the addon's exact method/signal names (`connect_to_broker`, `set_user_pass`, `subscribe`, `publish`, `is_connected_to_broker`, `on_broker_connected`, `on_message`) against the vendored source in Task 2 and adjust the thin wrapper accordingly — the addon is the only external unknown and its README documents these names.

- [ ] **Step 4: Run test, expect pass**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/run_headless.gd`
Expected: `PASS run_headless`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/mqtt_bridge.gd godot/tests/test_mqtt_bridge.gd
git commit -m "feat(godot): mqtt bridge with validation and bounded reconnect"
```

---

### Task 5: Refactor `main.gd` into a composition root

**Files:**
- Rewrite: `godot/main.gd`
- Create: `godot/scripts/world_builder.gd`, `track_builder.gd`, `signal_renderer.gd`, `crossing_controller.gd`, `camera_director.gd`, `hud.gd`, `train_controller.gd`, `wildlife_controller.gd`

**Interfaces:**
- Produces: a thin `main.gd` that constructs builders, wires `MqttBridge` signals into `TwinState` and scene nodes, and runs `_process`.
- Consumes: existing procedural builder functions in the current `godot/main.gd` (moved verbatim into the appropriate scripts).

- [ ] **Step 1: Move builder functions**

Move the existing functions from `godot/main.gd` into scripts with these public entry points (keep bodies unchanged in this task to avoid behaviour drift):

| From `main.gd` | To script | Public entry |
|---|---|---|
| `_build_environment`, `_build_forest`, `_build_mountain_tunnel`, `_add_ellipsoid`, `_material` | `world_builder.gd` | `build_environment(parent)`, `build_forest(parent, topology)` |
| `_build_track_and_terrain`, `_add_beam`, `_build_zone_boundary_gantries` | `track_builder.gd` | `build_track(parent) -> Path3D` |
| `_build_signals_and_crossing`, `_build_3aspect_signal`, `_set_signal_aspect` | `signal_renderer.gd` | `build_masts(parent, topology)`, `apply_aspects(aspects: Dictionary)` |
| barrier/flasher update logic | `crossing_controller.gd` | `build(parent, position)`, `update(delta, hazard: bool)` |
| `_build_cameras`, `_update_cameras` | `camera_director.gd` | `build(parent)`, `update(delta, focus: Transform3D)`, `cycle()` |
| `_build_hud`, `_update_hud` | `hud.gd` | `build(parent)`, `update(state: TwinState, status: String, stale: bool)` |
| train build/update | `train_controller.gd` | `build(parent, path)`, `render(trains: Array)`, `update(delta)` |
| elephant build/update | `wildlife_controller.gd` | `build(parent)`, `set_visible_zone1(bool)` |

- [ ] **Step 2: Rewrite `main.gd`**

Create the new `godot/main.gd`:

```gdscript
extends Node3D

var cfg: AppConfig
var twin: TwinState
var bridge: MqttBridge
var world; var track; var signals; var crossing; var cameras; var hud; var trains; var wildlife
var _path: Path3D

func _ready() -> void:
	cfg = AppConfig.load_default()
	twin = TwinState.new()
	bridge = MqttBridge.new()
	bridge.configure(cfg)
	add_child(bridge)
	bridge.snapshot_received.connect(_on_snapshot)
	bridge.block_signal.connect(_on_block_signal)
	bridge.status_changed.connect(func(_s): pass)

	world = preload("res://scripts/world_builder.gd").new()
	track = preload("res://scripts/track_builder.gd").new()
	signals = preload("res://scripts/signal_renderer.gd").new()
	crossing = preload("res://scripts/crossing_controller.gd").new()
	cameras = preload("res://scripts/camera_director.gd").new()
	hud = preload("res://scripts/hud.gd").new()
	trains = preload("res://scripts/train_controller.gd").new()
	wildlife = preload("res://scripts/wildlife_controller.gd").new()

	world.build_environment(self)
	_path = track.build_track(self)
	world.build_forest(self, twin)
	signals.build_masts(self, twin)
	crossing.build(self, Vector3(3.5, 0, -5.5))
	cameras.build(self)
	hud.build(self)
	trains.build(self, _path)
	wildlife.build(self)
	bridge.start()

func _on_snapshot(parsed: Dictionary) -> void:
	if twin.apply_snapshot(parsed):
		trains.render(twin.trains)
		signals.apply_aspects_from_state(twin)

func _on_block_signal(block: String, aspect: String) -> void:
	twin.apply_block_signal(block, aspect)
	signals.apply_aspects_from_state(twin)

func _process(delta: float) -> void:
	cameras.update(delta, trains.focus_transform())
	wildlife.update(delta)
	trains.update(delta)
	var now := Time.get_ticks_msec()
	hud.update(twin, bridge._status, twin.is_stale(now))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_camera"): cameras.cycle()
	elif event.is_action_pressed("toggle_wildlife_1"):
		wildlife.set_visible_zone1(not wildlife.zone1_visible)
		bridge.publish_wildlife("zone1", wildlife.zone1_visible)
	elif event.is_action_pressed("toggle_wildlife_2"):
		wildlife.set_visible_zone2(not wildlife.zone2_visible)
		bridge.publish_wildlife("zone2", wildlife.zone2_visible)
```

- [ ] **Step 3: Headless load check**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path godot --quit 2>&1 | grep -iE "error|parse"` 
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add godot/main.gd godot/scripts/*.gd
git commit -m "refactor(godot): split prototype into composition root and builders"
```

---

### Task 6: Double-track world with blocks and station

**Files:**
- Modify: `godot/scripts/track_builder.gd`
- Create: `godot/tests/test_track_builder.gd`

**Interfaces:**
- Produces: `build_track(parent) -> Path3D` now builds two `Path3D` loops (`UP`,`DOWN`), block markers matching `UP-B{i}`/`DOWN-B{i}` id convention (mirroring `backend/config.js` topology: 5 blocks/line), and a station/crossover set at indices 2.
- Produces: `block_map() -> Dictionary` mapping block id → world `Transform3D` (for signal placement).

- [ ] **Step 1: Write the failing test**

Create `godot/tests/test_track_builder.gd`:

```gdscript
class_name TestTrackBuilder
extends RefCounted

static func run() -> Array:
	var failures: Array[String] = []
	var tb = load("res://scripts/track_builder.gd").new()
	var ids := tb.block_id_list()
	if ids.size() != 10: failures.append("expected 10 blocks, got %d" % ids.size())
	if not ids.has("UP-B0") or not ids.has("DOWN-B4"): failures.append("block ids")
	return failures
```

Append to `run_headless.gd`.

- [ ] **Step 2: Run to verify it fails**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/run_headless.gd`
Expected: FAIL (`block_id_list` not found).

- [ ] **Step 3: Implement**

Add to `godot/scripts/track_builder.gd`:

```gdscript
const BLOCKS_PER_LINE := 5
const LINES := ["UP", "DOWN"]

func block_id_list() -> Array:
	var out: Array = []
	for line in LINES:
		for i in range(BLOCKS_PER_LINE):
			out.append("%s-B%d" % [line, i])
	return out
```

Extend `build_track` to create two parallel `Path3D` loops offset laterally by ~6 m, storing them as `paths`/`block_transforms`, and place block-boundary marker meshes and station platforms/crossover geometry at index 2. Block ids in `block_transforms` must exactly match `block_id_list()`.

- [ ] **Step 4: Run test, expect pass; headless load check**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/run_headless.gd && ~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path godot --quit 2>&1 | grep -iE "error|parse"`
Expected: `PASS run_headless`; no errors.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/track_builder.gd godot/tests/test_track_builder.gd
git commit -m "feat(godot): double-track world with blocks and station"
```

---

### Task 7: Multi-train rendering from authoritative state

**Files:**
- Modify: `godot/scripts/train_controller.gd`

**Interfaces:**
- Produces: `render(trains: Array)` creating/retiring visual consists by `id`, positioning them from `block`+`offsetM` via `track_builder.block_map()`, and `focus_transform()` + `update(delta)` for interpolation/chase camera.

- [ ] **Step 1: Implement `render`/`update`**

`render(trains)` stores the latest targets keyed by id; `update(delta)` lerps each consist's transform toward its target (using the block transform + offset along the path). Retire consists absent from the list. Coaches follow the consist with fixed offsets; loop wrap uses `PathFollow3D` so there is no visible teleportation.

- [ ] **Step 2: Headless load check**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path godot --quit 2>&1 | grep -iE "error|parse"`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add godot/scripts/train_controller.gd
git commit -m "feat(godot): render authoritative multi-train state"
```

---

### Task 8: Signal rendering from authoritative state

**Files:**
- Modify: `godot/scripts/signal_renderer.gd`

**Interfaces:**
- Produces: `build_masts(parent, twin)` creating one three-aspect mast per block at `track_builder.block_map()`, and `apply_aspects_from_state(twin)` setting each mast's lamp from `twin.blocks[i].signal`, defaulting to the zone signal when a block signal is absent.

- [ ] **Step 1: Implement**

`apply_aspects_from_state` reads `twin.blocks`, maps each block id to its mast, and shows exactly one lamp (`GREEN`/`YELLOW`/`RED`). If a block has no signal, fall back to `twin.zones[block.zone].signal`. No aspect is ever derived locally.

- [ ] **Step 2: Headless load check**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path godot --quit 2>&1 | grep -iE "error|parse"`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add godot/scripts/signal_renderer.gd
git commit -m "feat(godot): render per-block authoritative signal aspects"
```

---

### Task 9: HUD — status, blocks, trains, stale/offline

**Files:**
- Modify: `godot/scripts/hud.gd`

**Interfaces:**
- Produces: `build(parent)` and `update(twin, status, stale)` showing link status (`SYNCING`/`LIVE`/`OFFLINE`), last-state age, per-zone signal, per-block aspect summary, train list (id/speed/block), the illustrative stopping distance, and the simulation disclaimer.

- [ ] **Step 1: Implement**

Render: header with status dot (green `LIVE`, amber stale, red `OFFLINE`), zone signals, a compact block strip, a train list, and the disclaimer line "SIMULATION — not certified railway equipment". Keep the existing dark glass style.

- [ ] **Step 2: Headless load check**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path godot --quit 2>&1 | grep -iE "error|parse"`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add godot/scripts/hud.gd
git commit -m "feat(godot): multi-train/block HUD with stale state indicator"
```

---

### Task 10: Verification — headless load, ACL, integration, checklist

**Files:**
- Modify: `godot/tests/run_headless.gd`
- Modify: `README.md`

- [ ] **Step 1: Headless load/parse gate**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path godot --quit`
Expected: exits 0 with no script/resource errors.

- [ ] **Step 2: Headless unit harness**

Run: `~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --script res://tests/run_headless.gd`
Expected: `PASS run_headless`.

- [ ] **Step 3: ACL check (requires solver from S0 Task 9)**

Run: `bash scripts/test-backend.sh`
Expected: Godot ACL cases pass (only `railway/zoneN/wildlife` write allowed; `railway/signal/+` read allowed; no train/state/command writes).

- [ ] **Step 4: Backend integration (manual, documented)**

With the stack up: start Godot, confirm `SYNCING` → `LIVE`, confirm the HUD train list and block aspects match `GET /api/state`, toggle wildlife and confirm only the intended zone changes and the backend sets that zone `RED`.

- [ ] **Step 5: README note**

Add a "Godot twin" subsection documenting `config.cfg` (MQTT), the `godot --headless` checks, and the Godot input map. Record the Godot version used.

- [ ] **Step 6: Commit**

```bash
git add godot/tests/run_headless.gd README.md
git commit -m "test(godot): headless verification + document twin setup"
```

---

## Self-Review

**Spec coverage:** addon + MQTT (§3 → Tasks 2, 4); topics and validation (§3.2 → Task 4); lifecycle (§3.3 → Task 4); renderer/quality (§4 → Task 1; full tiers deferred to C2); scene architecture (§6 → Tasks 5–9); double track/blocks/station (§7 → Task 6); multi-train (§8 → Task 7); signals (§9 → Task 8); HUD (§9 → Task 9); config (§12 → Task 1); verification (§14 → Task 10). Asset/animation/scenario/cinematic sections (§5, §10, §13) are explicitly deferred to plan **C2**.

**Placeholder scan:** No `TBD`/`TODO`. Two tasks intentionally instruct reading an external artefact at execution time (the vendored addon's exact API in Task 4; the moved builder bodies in Task 5) — these are concrete, verifiable steps, not placeholders.

**Type consistency:** `AppConfig`/`TwinState`/`MqttBridge` names and signatures are used consistently; `block_id_list()` mirrors the backend `UP-B{i}` convention introduced in S0; `apply_aspects_from_state` is referenced by `main.gd` and defined in Task 8.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-19-stage-c-godot-twin-integration.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks.

**2. Inline Execution** — execute in-session with checkpoints (`superpowers:executing-plans`).
