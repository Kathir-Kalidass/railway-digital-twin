# Stage E acceptance record

Date: 2026-10-21
Host: Linux (WSL, headless), Godot 4.7.2, PlatformIO, Node.js 22.

Educational simulation only; not certified railway equipment.

## Automated gate

| Surface | Command | Result |
|---|---|---|
| Godot headless | `bash godot/tests/run_tests.sh` | PASS (12 suites) |
| ESP32 host logic | `cd esp32 && pio test -e native` | PASS (14 cases) |
| Backend | `bash scripts/test-backend.sh` | PASS (56 tests) |
| Web build | `cd web && npm run build` | PASS |
| ESP32 firmware | `cd esp32 && pio run -e esp32dev` | PASS (1.2 MB image, 87% flash) |

Godot suites: `test_parse`, `test_port_helpers`, `test_scene_load`,
`test_lts_full_enhance`, `test_mqtt_bridge`, `test_train_reconciler`,
`test_wildlife_publisher`, `test_e2e_safety`, `test_camera_director`, `test_hud`, `test_scenario_director`, `test_real_assets`.

Notes:

- The Godot e2e test drives the real `MQTTBridge.message_received` signal into
  `TrainReconciler`; hazard → 0 km/h and clear → resume are asserted without
  requiring a broker.
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
  references. Wokwi runtime checks still require the VS Code extension or a
  Wokwi account; no Wokwi CLI is installed here.
- `test_real_assets` verifies the tracked Blender exports: the LTS wagon GLBs
  replace the procedural carriages, deer/elephant GLBs spawn with articulated
  limbs, and the full-scale scenery/terrain is populated. The scene was also
  captured with Mesa llvmpipe (software) and with the WSLg D3D12 GPU path
  (`MESA_LOADER_DRIVER_OVERRIDE=d3d12 GALLIUM_DRIVER=d3d12`, under `xvfb-run`
  for clean buffers) to check framing, lighting, cameras, HUD, and animals.
  WSLg D3D12 reported about 11.8 ms GPU render time per frame at 1280x720 in a
  150-frame MovieWriter run; screenshots were used for visual QA only.

## Manual demo

The Windows GPU checklist is `docs/demo-windows.md`. The visual subset was
exercised on the WSLg D3D12 GPU path on 2026-10-21; the Windows host run is
still required for the dashboard, ESP32/Wokwi, and full safety-sequence checks.

## Regenerate

```bash
bash godot/tests/regress.sh; echo "exit=$?"
```
