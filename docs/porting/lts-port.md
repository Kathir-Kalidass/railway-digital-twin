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
| `godot/src/{ltstrack,ltstrain,lts_world}.gd` | Compose an LTS `Rail` track, load the curated LTS wagon GLBs when present (procedural fallback), and add LTS unit conversion, speed controls, and follow camera | Runnable Godot 4 scene without the ignored upstream asset pack |
| `godot/src/mqtt_bridge.gd` | Load broker settings from local config, queue subscriptions, validate JSON-object messages, and retry failed connections with bounded exponential backoff | Overlay MQTT connection lifecycle |
| `godot/src/train_reconciler.gd` | Consume backend signal, speed, and command schemas and write only through `LTSTrain.set_target_speed_kmh()`; subscribe only to topics allowed by the Godot broker ACL | Keep train safety targets synchronized without subscribing to the backend-only `railway/state` topic |
| `godot/src/wildlife_publisher.gd` | Publish changed wildlife observations on the zone wildlife topic | Twin-to-backend wildlife observations |
| `godot/src/{detection_band,wildlife_spawner}.gd` | Spawn Blender deer/elephant GLBs with articulated gait, fall back to capsules, and publish matching-species entry/exit counts | Runtime detection with or without asset packs |
| `godot/scenes/lts_full.tscn` | Full-scale scene: LTS track/train, station, buildings, catenary, procedural terrain, wildlife, safety, cameras, and HUD. Renamed from `lts_minimal.tscn` | Runnable Godot 4 LTS-led simulation scene |
| `godot/src/{scenery_director,animal_visual,terrain_generator}.gd` | Populate the station (canopies, footbridge, lamps, signs), tree line, wires and foothills; animate animal limbs; flatten/generate terrain around the curve | Full-scale presentation without hand-placed editor content |

## Curated Blender exports

`tools/export_lts_assets.sh` runs Blender headless against the upstream
`.blend` library and writes texture-size-capped GLBs to
`godot/assets/models/lts/`. The passenger wagon and driver-stand EMU use the
detailed (non-baked) material variants because the upstream baked textures were
not included in the snapshot. `tools/build_animals.py` and
`tools/build_trees.py` generate the deer/elephant and foliage models with
separate limb/joint origins; `godot/src/animal_visual.gd` animates the limbs.

The curated GLBs are tracked (about 16 MB); Godot's extracted sidecar PNGs,
`.import` files, and `.uid` files are ignored. Regenerate with Blender 4.x:

```bash
bash tools/export_lts_assets.sh      # train, station, scenery
blender -b -P tools/build_animals.py # deer + elephant
blender -b -P tools/build_trees.py   # oak, pine, birch, bush
```

## Validation scope

`bash godot/tests/run_tests.sh` imports the Godot project and runs the parse,
port-helper, LTS full-scene/motion, real-model, MQTT reconnect,
backend-schema reconciliation, wildlife publishing, end-to-end safety,
cinematic-reel, and camera/day-night tests (12 suites). A live bridge smoke
check also connected to the local broker and published a wildlife payload.

`godot/scenes/lts_full.tscn` is the project startup scene; the former
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
- Curated exports (`godot/assets/models/`, ~16 MB) are tracked; the upstream
  checkout and the full texture tree remain ignored.
- Generated Godot `.uid`, `.import`, `.godot/`, and extracted sidecar textures
  (`assets/models/lts/*.png`) are ignored.
- Runtime paths fall back to procedural geometry when the optional LTS assets
  are absent.
