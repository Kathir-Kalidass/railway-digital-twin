# Stage E acceptance record

Date: 2026-10-21
Host: Linux (WSL, headless), Godot 4.7.2, PlatformIO, Node.js 22.

Educational simulation only; not certified railway equipment.

## Automated gate

| Surface | Command | Result |
|---|---|---|
| Godot headless | `bash godot/tests/run_tests.sh` | PASS (16 suites) |
| ESP32 host logic | `cd esp32 && pio test -e native` | PASS (14 cases) |
| Backend | `MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test` (isolated broker) | PASS (84 tests) |
| Web build | `cd web && npm run build` | PASS |
| ESP32 firmware | `cd esp32 && pio run -e esp32dev` | PASS (1.2 MB image, 87% flash) |

Godot suites: `test_parse`, `test_port_helpers`, `test_scene_load`,
`test_lts_full_enhance`, `test_mqtt_bridge`, `test_train_reconciler`,
`test_wildlife_publisher`, `test_e2e_safety`, `test_camera_director`, `test_hud`,
`test_scenario_director`, `test_real_assets`, `test_train_loop`,
`test_wildlife_safety`, `test_river_bridges`, `test_esp32_integration`.

Notes:

- The Godot e2e test drives the real `MQTTBridge.message_received` signal into
  `TrainReconciler`; hazard → 0 km/h and clear → resume are asserted without
  requiring a broker.
- `test_esp32_integration` emits ESP32 telemetry into the real scene, asserts one
  detection-driven animal, STOP/barrier-down, and release on the clear edge.
  A live broker check on port 1884 also verified ESP32 telemetry → backend →
  Godot: detection produced `STOP`/RED and clear left the backend in
  `RECOVERY_REQUIRED` with RED and target 0.
- `test_mqtt_bridge` exercises connection-failure backoff against a closed port.
- Backend tests need a broker for the ACL/e2e cases. With the host broker
  unavailable they run against a disposable container on 1884:
  `docker run -d --rm --name rdt-test-mqtt -p 127.0.0.1:1884:1883
  -v "$PWD/mosquitto:/mosquitto/config:ro" eclipse-mosquitto:2`, then
  `MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test`. The suite uses
  `--test-force-exit` because some MQTT clients intentionally keep handles open.
- A host-level Mosquitto service can occupy port 1883 and shadow the Compose
  broker, which makes ACL tests appear to fail. Stop it (`sudo systemctl stop
  mosquitto`) before `docker compose up -d mqtt`.
- The firmware build downloads the espressif32 toolchain on first use; it is
  slow but only the compile step depends on it. The current build succeeds and
  produces `esp32/.pio/build/esp32dev/firmware.bin`, which `wokwi.toml` already
  references.
- Wokwi CLI v0.29.0 is installed at `~/.wokwi/bin/wokwi-cli` (it is not on the
  default `PATH`). The diagram lints clean (one informational notice for the
  ESP32 board type). A Pinggy raw-TCP tunnel plus `scenarios/wildlife.yaml`
  completed against the local broker: the serial log showed `MQTT connected`
  and `STATE LOCAL WILDLIFE`, and the live Godot monitor observed the external
  edge (`external=true`, `STOP`, RED) followed by release while the backend
  stayed in `RECOVERY_REQUIRED`/RED.
- The host `mosquitto` service was listening on `127.0.0.1:1883` during this
  verification. Backend tests were run against a disposable Mosquitto container
  on port 1884 (`MQTT_URL=mqtt://127.0.0.1:1884`) so they did not hit the host
  broker. Recreate the Compose MQTT container before using the normal stack.
- `test_real_assets` verifies the tracked Blender exports: the LTS wagon GLBs
  replace the procedural carriages, deer/elephant GLBs spawn with articulated
  limbs, and the full-scale scenery/terrain is populated. The scene was also
  captured with Mesa llvmpipe (software) and with the WSLg D3D12 GPU path
  (`MESA_LOADER_DRIVER_OVERRIDE=d3d12 GALLIUM_DRIVER=d3d12`, under `xvfb-run`
  for clean buffers) to check framing, lighting, cameras, HUD, and animals.
  WSLg D3D12 reported about 11.8 ms GPU render time per frame at 1280x720 in a
  150-frame MovieWriter run; screenshots were used for visual QA only.

## Phase 1 feature verification (2026-10-21)

| Enhancement | Evidence |
|---|---|
| Seamless infinite loop with moving train | `test_train_loop` PASS; track length 753.9822 m at radius 120 m; train and carriage positions wrap with `fposmod` |
| Visible wildlife crossing the rails | `test_wildlife_safety` PASS; `scene_wildlife.png` capture shows deer and lowered barrier; crossings are direct at a fixed level crossing |
| Local warn/stop fail-safe layered with backend authority | `test_wildlife_safety`, `test_train_reconciler`, and `test_e2e_safety` PASS; local limit can only tighten the target |
| River channel, water, road bridge, and two railway bridges | `test_river_bridges` PASS; procedural channel and `RiverWater`; bridges aligned at river crossings |
| Level-crossing alarm and barrier | `test_wildlife_safety` asserts alarm and barrier-down after actuation; visible in `scene_wildlife.png` |
| ESP32 telemetry drives the twin | `test_esp32_integration`; local live MQTT check; cloud Wokwi scenario through Pinggy PASS (serial `STATE LOCAL WILDLIFE`, Godot `external=true` → STOP/RED) |

Deferred by the approved phased scope: wildlife-underpass preference and the
Phase 2 visual slices. The Phase 2 design is recorded separately.

## Stage 2A backend-live verification (2026-10-21)

Slice 2A is implemented on branch `master`. The backend is authoritative for two
trains (`T1` UP, `T3` DOWN), ten blocks, per-block aspects, station dwell state,
and one station crossover pair (`UP-B2 <-> DOWN-B2`).

| Item | Evidence |
|---|---|
| Two-train fleet state | `state.test.js` exposes `trains`, `lines`, `blocks`, `station`, `routes`; `config.test.js` asserts `T1`/`T3`, `753.9822 m` UP, `728.8495 m` DOWN |
| Per-block aspects and retained MQTT signals | `signalling.test.js`, `bus.test.js`; `bus.snapshot()` publishes retained `railway/signal/{blockId}` |
| Occupancy safety | `simulation.test.js` holds a train at the boundary of a RED block, and lets it continue past a RED block occupied by its own overlapping consist (`f55f872`); `routes.js` rejects occupied crossover destinations |
| Crossover interlock | `routes.test.js` grants one route at a time, rejects hazards/occupancy, releases after clear; `POST /api/route` audited with `route:set` RBAC |
| Fixed-timestep loop | `loop.test.js` ticks `state` and publishes a snapshot; `server.js` starts the loop on MQTT connect and stops it on close |
| ACL least privilege | `broker_acl.test.js`; godot reads `railway/state` and `railway/signal/+` and can no longer write `railway/zoneN/train`; esp32 cannot read block signals |
| Legacy endpoint removed | `POST /api/event` returns 404 (`control_routes.test.js`); `/api/speed` accepts `trainId` and rejects unknown IDs |
| Live server check | `node backend/server.js` on the isolated broker published `railway/state` at 2 Hz with `T1`/`T3` moving and retained per-block signals for `UP-B0`/`DOWN-B0` |
| Live crossover grant | With `T3` held via `/api/speed`, `POST /api/route` (`X-UP-DOWN`) returned the active route and moved `T1` from `UP-B2` to `DOWN-B2`; the same request while `T3` occupied the destination correctly returned 409 |
| Regression | Backend 84/84, Godot 16/16, ESP32 native 14/14, `pio run -e esp32dev` PASS, `web` build PASS |

The legacy `snapshot().train` summary is retained for un-migrated clients. Godot
and ESP32 integrations still pass unchanged; visual double-track rendering and
meet/pass remain in slices 2B–2E.

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

## Manual demo

The Windows GPU checklist is `docs/demo-windows.md`. The visual subset was
exercised on the WSLg D3D12 GPU path on 2026-10-21. The local ESP32→backend→
Godot path and the cloud Wokwi scene were exercised through MQTT; the Windows
host run is still required for the dashboard and physical-hardware checks.

## Regenerate

```bash
bash godot/tests/regress.sh; echo "exit=$?"
```
