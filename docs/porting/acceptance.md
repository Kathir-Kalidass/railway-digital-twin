# Stage E acceptance record

Date: 2026-10-21
Host: Linux (WSL, headless), Godot 4.7.2, PlatformIO, Node.js 22.

Educational simulation only; not certified railway equipment.

## Automated gate

| Surface | Command | Result |
|---|---|---|
| Godot headless | `bash godot/tests/run_tests.sh` | PASS (16 suites) |
| ESP32 host logic | `cd esp32 && pio test -e native` | PASS (14 cases) |
| Backend | `MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test` (isolated broker) | PASS (58 tests) |
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
- Backend tests start Mosquitto through `scripts/test-backend.sh` so the broker
  ACL and end-to-end cases run instead of timing out. The suite uses
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

Deferred by the approved phased scope: wildlife-underpass preference, double
track, track interchange/crossover, and multi-train meet/pass signalling. The
Phase 2 design is recorded separately.

## Manual demo

The Windows GPU checklist is `docs/demo-windows.md`. The visual subset was
exercised on the WSLg D3D12 GPU path on 2026-10-21. The local ESP32→backend→
Godot path and the cloud Wokwi scene were exercised through MQTT; the Windows
host run is still required for the dashboard and physical-hardware checks.

## Regenerate

```bash
bash godot/tests/regress.sh; echo "exit=$?"
```
