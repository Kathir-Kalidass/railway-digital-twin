# Stage E acceptance record

Date: 2026-10-20
Host: Linux (WSL, headless), Godot 4.7.2, PlatformIO, Node.js 22.

Educational simulation only; not certified railway equipment.

## Automated gate

| Surface | Command | Result |
|---|---|---|
| Godot headless | `bash godot/tests/run_tests.sh` | PASS (8 suites) |
| ESP32 host logic | `cd esp32 && pio test -e native` | PASS (14 cases) |
| Backend | `bash scripts/test-backend.sh` | PASS (56 tests) |
| Web build | `cd web && npm run build` | PASS |
| ESP32 firmware | `cd esp32 && pio run -e esp32dev` | PENDING (toolchain download) |

Godot suites: `test_parse`, `test_port_helpers`, `test_scene_load`,
`test_lts_full_enhance`, `test_mqtt_bridge`, `test_train_reconciler`,
`test_wildlife_publisher`, `test_e2e_safety`, `test_camera_director`, `test_hud`, `test_scenario_director`.

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
  slow but only the compile step depends on it.

## Manual demo

The Windows GPU checklist is `docs/demo-windows.md`. It remains unverified in
this environment because WSL has no GPU; run it on the Windows host and fill in
the results table.

## Regenerate

```bash
bash godot/tests/regress.sh; echo "exit=$?"
```
