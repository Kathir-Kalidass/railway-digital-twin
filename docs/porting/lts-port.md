# Libre-TrainSim to Godot 4.7 port log

Source: `Libre-TrainSim-master/src` (v0.9.beta1, GPL v3). It is a Godot 3.x
project with `format=2` scenes; the `config_version=5` value in upstream's
`project.godot` does not make it a Godot 4 project.

The source's project-root references (`res://Data/...`, `res://Resources/...`)
require the port to live at `godot/Data/` and `godot/Resources/`. Runtime code
is copied from the provided `Libre-TrainSim-master/` checkout, then ported in
place. Editor, modding, translation, and unused UI code is excluded. The
upstream binary `Resources/` assets are local-only and ignored; they must not
be required for parse tests or core operation.

## Porting decisions

- Keep LTS `res://Data` and `res://Resources` paths intact rather than rewriting
  hundreds of source references.
- Keep GPL v3 attribution in `godot/LICENSE` and `godot/CREDITS.md`.
- Use procedural fallback ground when source assets/scenes are unavailable.
- Parse-test the selected runtime scripts; do not require unrelated legacy UI
  scripts or upstream binary assets to load.
- MQTT remains in the overlay (`godot/src/`) and is not added to LTS runtime.

## Change log

| File | Change | Godot 3 symbol / issue |
|---|---|---|
| `godot/Data/Scripts/Singletons/Math.gd` | Convert integer/string formatting with `str()`, use `Array.reverse()` and `Array.remove_at()` | `String(int)`, `Array.invert()`, `Array.remove()` |
| `godot/Data/Scripts/Singletons/Root.gd` | Use `DirAccess.open()` and `String.path_join()`; rename signal emitter to `emit_world_origin_shifted()`; skip `.` and `..` during recursive scans | `DirAccess.new()`, `plus_file()`, signal/function name collision, directory recursion |
| `godot/Data/Scripts/Singletons/input_helper.gd` | Map old joystick constants to Godot 4 `JOY_BUTTON_*`/`JOY_AXIS_*`; use helper axis labels instead of removed `Input.get_joy_axis_string()` | `JOY_XBOX_*`, `JOY_SONY_*`, `JOY_ANALOG_*`, `Input.get_joy_axis_string()` |
| `godot/Data/Scripts/chunk.gd` | Use typed rail names and typed signal connection; create a procedural ground plane instead of preloading ignored asset scenes | Godot 3 untyped export array; missing/unimported `Resources/` assets |
| `godot/Data/Scripts/Rail.gd` | Replace the Godot 3 global singleton reference with a runtime root lookup and retain Godot 4-compatible rail construction | Autoload access in headless `--script` tests |
| `godot/Data/Scripts/world_object.gd` | Resolve global helpers through the scene tree instead of relying on editor-only autoload identifiers | Autoload access in headless `--script` tests |
| `godot/addons/godot-mqtt/mqtt.gd` | Add `class_name MQTTClient`; source and pin recorded with MIT license | Script otherwise unavailable as a named global class |
| `godot/src/{ltstrack,ltstrain,lts_world}.gd` | Compose an LTS `Rail` track with a procedural articulated train, LTS unit conversion, speed controls, and follow camera | Small runnable Godot 4 scene without the ignored upstream asset pack |
| `godot/src/mqtt_bridge.gd` | Load broker settings from local config, queue subscriptions, validate JSON-object messages, and retry failed connections with bounded exponential backoff | Overlay MQTT connection lifecycle |
| `godot/src/train_reconciler.gd` | Consume backend signal, speed, and command schemas and write only through `LTSTrain.set_target_speed_kmh()`; subscribe only to topics allowed by the Godot broker ACL | Keep train safety targets synchronized without subscribing to the backend-only `railway/state` topic |
| `godot/src/wildlife_publisher.gd` | Publish changed wildlife observations on the zone wildlife topic | Twin-to-backend wildlife observations |
| `godot/src/{detection_band,wildlife_spawner}.gd` | Give procedural wildlife collision areas and publish matching-species entry/exit counts | Runtime detection without external animal assets |
| `godot/scenes/lts_minimal.tscn` | Compose LTS track/train, follow camera, MQTT bridge, safety reconciler, procedural terrain, wildlife detector, bridge, and underpass | Runnable Godot 4 LTS-led simulation scene |

## Validation scope

`bash godot/tests/run_tests.sh` imports the Godot project and runs the parse,
port-helper, LTS scene/motion, MQTT reconnect, backend-schema reconciliation,
and wildlife publishing tests. A live bridge smoke check also connected to the
local broker and published a wildlife payload.

`godot/scenes/lts_minimal.tscn` is the project startup scene; the former
procedural demo remains available at `godot/scenes/procedural_twin.tscn`.
Godot's 3-to-4 editor conversion was tested in an isolated scratch project.
Some upstream scenes remain `format=2`: two chunk prefab scenes are absent from
the imported subset, and the grass/world-pattern scenes reference ignored
upstream assets or scripts not included in the minimal port. They are not
runtime dependencies; the LTS-led scene uses the ported rail script and
procedural fallbacks instead.

## Repository hygiene

- The upstream checkout (`Libre-TrainSim-master/`, ~1.5 GB), its asset tree
  (`godot/Resources/`, ~678 MB) and the train models (`godot/Trains/`,
  ~141 MB) are local-only and ignored by git.
- Tracked tree size after cleanup: ~7.7 MB (`git ls-files -z | xargs -0 du -ch`).
- Generated Godot `.uid` files are ignored; no `.import`, `.godot/`, or
  upstream binaries are tracked.
- Runtime paths fall back to procedural geometry when the optional LTS assets
  are absent.
