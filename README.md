# Railway Digital Twin with Wildlife Safety (educational simulation)

A runnable digital twin integrating a Godot 4 3D forest railway, trusted Node.js control plane, React dashboard, Mosquitto MQTT broker (authenticated + ACLs), and ESP32 firmware.

## Architecture

- **Mosquitto broker (TCP 1883 / WS 9001):** `allow_anonymous false` with per-client credentials (`godot`, `esp32`, `backend`, `dashboard`) and topic ACLs.
- **Node.js backend (trusted control plane):** Authenticates users via bcrypt & JWT, enforces RBAC (`viewer`, `operator`, `admin`), validates command envelopes, prevents command replay via SQLite registry, logs audit events, manages a two-zone state machine (`zone1`, `zone2`), and is the **sole publisher** of commands, state snapshots, and alerts.
- **React dashboard:** Authenticated web interface. Viewers can monitor state; operators can issue control commands; admins can inspect audit logs. Control actions flow through REST + JWT; dashboard reads live updates via WebSocket.
- **Godot twin:** 3D procedural railway world with curved movement, animated train/wildlife, dynamic signals, barriers, and cameras. Subscribes to commands and reports zone telemetry.
- **ESP32 controller:** Authenticated MQTT IoT node providing edge sensing and restrictive signal fail-safe outputs.

> **Safety:** this is a classroom digital-twin simulation, not railway safety equipment. Do not connect it to real signalling, trains, or operational infrastructure. “Stopping distance” is a visualization estimate only.

## Requirements

- Godot 4.2+ (runs on host/Windows)
- Docker Engine with Compose
- Node.js 22+ (if running backend/web outside Docker)

## Quick start

1. Setup broker passwords and start the stack:
   ```bash
   ./scripts/dev-up.sh
   ```
2. Open dashboard: http://localhost:5173
   - Seed users:
     - `viewer` / `viewer-dev-pass`
     - `operator` / `operator-dev-pass`
     - `admin` / `admin-dev-pass`
3. Launch Godot and run `godot/project.godot`.

## Topic Contract & ACLs

| Client | Role | Publish | Subscribe |
|---|---|---|---|
| `backend` | Sole control authority | `railway/state`, `railway/events`, `railway/alerts`, `railway/zone*/signal`, `railway/commands/*`, `railway/speed/*`, `railway/security/events` | `railway/zone*/train`, `railway/zone*/wildlife`, `railway/telemetry/esp32` |
| `godot` | 3D twin telemetry | `railway/zone1/train`, `railway/zone1/wildlife`, `railway/zone2/train`, `railway/zone2/wildlife` | `railway/commands/zone1`, `railway/commands/zone2`, `railway/speed/zone1`, `railway/speed/zone2`, `railway/zone1/signal`, `railway/zone2/signal` |
| `dashboard` | Read-only client | *(none)* | `railway/state`, `railway/events`, `railway/alerts` |
| `esp32` | IoT controller | `railway/telemetry/esp32` | `railway/commands/esp32` |
