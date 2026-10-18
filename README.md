# Railway Digital Twin with Wildlife Safety (educational simulation)

A runnable starter integrating a Godot 4 3D forest railway, Node.js MQTT/REST bridge, React dashboard, Mosquitto, and ESP32 firmware.

## Architecture

- **Godot** owns the animated 3D world and sends simulated sensor events to the backend over HTTP.
- **Node.js backend** publishes state/events to MQTT and exposes REST endpoints for dashboard controls.
- **React dashboard** polls the backend and can trigger wildlife, sensor-fault, and reset scenarios.
- **ESP32** subscribes to `railway/commands` and publishes controller telemetry to `railway/telemetry`.

Godot uses HTTP to the bridge rather than implementing MQTT in GDScript. MQTT is the shared event bus for the backend, dashboard bridge, and ESP32. This keeps the project dependency-light and makes the integration explicit.

> **Safety:** this is a classroom digital-twin simulation, not railway safety equipment. Do not connect it to real signalling, trains, or operational infrastructure. “Stopping distance” is a visualization estimate only.

## Requirements

- Godot 4.2+ (4.x recommended)
- Docker Desktop / Docker Engine with Compose
- Node.js 20+ and npm (only if running backend/web outside Docker)
- Arduino IDE or PlatformIO for ESP32 firmware

## Quick start

1. Start MQTT + backend + dashboard:
   ```bash
   docker compose up --build
   ```
2. Open dashboard: http://localhost:5173
3. Open `godot/project.godot` with Godot 4.x and press **F6/F5** (run project).
4. In Godot, use the on-screen controls or keyboard:
   - `Space`: toggle wildlife intrusion
   - `F`: toggle sensor fault
   - `R`: reset scenario
   - `Up` / `Down`: adjust target speed
5. The Godot simulation calls `http://localhost:3001/api/event`. The backend publishes events to MQTT and the dashboard updates.

### If Godot is running in a different machine/container
Edit `API_BASE` in `godot/main.gd` to the backend's reachable address. `localhost` means the computer running Godot.

## MQTT topics

| Topic | Direction | Payload |
|---|---|---|
| `railway/state` | backend → subscribers | current zone, signal, speed, hazard, sensor health |
| `railway/events` | backend → subscribers | timestamped events/alerts |
| `railway/commands` | dashboard/backend → ESP32 | `{"command":"..."}` |
| `railway/telemetry` | ESP32 → backend/subscribers | controller telemetry |

## Project layout

```text
railway-digital-twin/
├── docker-compose.yml
├── mosquitto/mosquitto.conf
├── backend/                 # REST + MQTT bridge
├── web/                     # React dashboard
├── godot/                   # procedural 3D simulation
└── esp32/                   # ESP32 MQTT firmware
```

## Run without Docker

Terminal 1: run Mosquitto with `mosquitto/mosquitto.conf`.

Terminal 2:
```bash
cd backend && npm install && npm run dev
```

Terminal 3:
```bash
cd web && npm install && npm run dev
```

## ESP32 / Wokwi setup

1. Open `esp32/` as an Arduino sketch or copy `railway_controller.ino` into an ESP32 project.
2. Use a broker reachable from the ESP32. In Wokwi, use the documented public gateway/broker reachability available to your setup; do not send sensitive data through public gateways.
3. Update `WIFI_SSID`, `WIFI_PASSWORD`, and `MQTT_HOST`. `localhost` will **not** work from a physical ESP32; use your computer's LAN IP and ensure firewall/broker listener configuration permits it.
4. Firmware listens for `railway/commands` and publishes `railway/telemetry`.

## Notes

- The default Mosquitto configuration is intentionally for local development only (anonymous access, local ports). Do not expose it to the internet.
- For a real deployment, add authentication, TLS, ACLs, schema validation, retained-state policy, reconnect/backoff, and audit logging.
- The Godot scene uses procedural primitive meshes so it runs without downloading third-party assets. Replace these with licensed train/elephant/tree models for a more realistic presentation.
