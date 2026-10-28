# Railway Digital Twin with Wildlife Safety (educational simulation)

A runnable digital twin integrating a Godot 4 3D forest railway, trusted Node.js control plane, React dashboard, Mosquitto MQTT broker (authenticated + ACLs), and ESP32 firmware.

## Architecture

- **Mosquitto broker (TCP 1883 / WS 9001):** `allow_anonymous false` with per-client credentials (`godot`, `esp32`, `backend`, `dashboard`) and topic ACLs.
- **Node.js backend (trusted control plane):** Authenticates users via bcrypt & JWT, enforces RBAC (`viewer`, `operator`, `admin`), validates command envelopes, prevents command replay via SQLite registry, logs audit events, manages a two-zone state machine (`zone1`, `zone2`), and is the **sole publisher** of commands, state snapshots, and alerts.
- **React dashboard:** Authenticated web interface. Viewers can monitor state; operators can issue control commands; admins can inspect audit logs. Control actions flow through REST + JWT; dashboard reads live updates via WebSocket.
- **Godot twin:** full-scale 3D railway world with an LTS-derived Blender train/station/scenery fleet, a 754 m closed loop, a carved river with road and railway bridges, a direct wildlife level crossing, catenary, dynamic signals, barriers, and cameras. Subscribes to authoritative state and reports wildlife observations.
- **ESP32 controller:** Authenticated MQTT IoT node providing edge sensing and restrictive signal fail-safe outputs.

> **Safety:** this is a classroom digital-twin simulation, not railway safety equipment. Do not connect it to real signalling, trains, or operational infrastructure. “Stopping distance” is a visualization estimate only.

## Current scope

**Phase 1 is implemented:** a closed single-track loop, direct wildlife level
crossing with a local warn/slow/stop fail-safe, visible boom barriers, and a river
with road/railway bridges. See `docs/porting/acceptance.md` for evidence.

**Phase 2 / Stage 2A is implemented:** the backend is authoritative for a
two-train double-track fleet, per-block aspects, a station crossover interlock,
per-train speed control, and retained per-block MQTT signals. The unauthenticated
`POST /api/event` shim is removed; `POST /api/route` is authenticated and
audited. Visual double-track rendering and meet/pass scenarios are implemented
in slices 2B–2E. See
`docs/superpowers/specs/2026-10-21-stage-c2-double-track-multitrain-design.md`.
The wildlife underpass remains scenery only in Phase 1.

## Conference paper

`responsible_ai_conference_paper/` holds the IEEE-format paper
*AI-Based Railway Track Defect Detection in India — False Negatives, Safety
Assurance and Human Accountability*, together with its LaTeX source, figures,
slide deck, and the scripts that regenerate them in place:

```bash
python3 responsible_ai_conference_paper/generate_figures.py   # fig_*.png
python3 responsible_ai_conference_paper/generate_ppt.py       # slide deck
cd responsible_ai_conference_paper
pdflatex Conference.tex && pdflatex Conference.tex            # Conference.pdf
```

## Requirements

- Docker Engine with Compose
- Node.js 22+
- npm and the local test toolchain for backend/web
- Optional: Godot 4.7+ for the Twin simulation
- Optional: PlatformIO for the ESP32 firmware compile checks

## Local setup

1. Copy the sample environment file and tune the local passwords before the first run:
   ```bash
   cp .env.sample .env
   ```
2. Start the stack and generate the broker credentials:
   ```bash
   ./scripts/dev-up.sh
   ```
3. Verify the backend is ready:
   ```bash
   curl -s http://localhost:3001/api/health
   ```
   Expected: `{"ok":true,"mqttConnected":true}`
4. Open the dashboard at http://localhost:5173
   - Seed users:
     - `viewer` / `viewer-dev-pass`
     - `operator` / `operator-dev-pass`
     - `admin` / `admin-dev-pass`
5. Launch Godot and run `godot/project.godot` if you are validating the twin view. The startup scene is `godot/scenes/lts_full.tscn`; press `B` for the cinematic reel, `C` to cycle cameras, and `SPACE` to trigger a deer crossing. Wildlife walks to the fixed level crossing and the local safety layer warns, slows, and stops the train; the boom barriers lower while the animal is on the track.

## Operational commands

- Start stack: `./scripts/dev-up.sh`
- Stop stack: `docker compose down`
- Rebuild after config changes: `docker compose up --build -d`
- Run backend regression suite: `npm --prefix backend test`
- Run web build: `cd web && npm run build`
- Run the full gate check: `./scripts/verify-all.sh`

## Broker auth and ACLs

| Client | Role | Publish | Subscribe |
|---|---|---|---|
| `backend` | Sole control authority | `railway/state`, `railway/events`, `railway/alerts`, `railway/zone*/signal`, `railway/commands/*`, `railway/speed/*`, `railway/security/events` | `railway/zone*/train`, `railway/zone*/wildlife`, `railway/telemetry/esp32` |
| `godot` | 3D twin telemetry | `railway/zone1/train`, `railway/zone1/wildlife`, `railway/zone2/train`, `railway/zone2/wildlife`, `railway/telemetry/esp32` (read-only) | `railway/commands/zone1`, `railway/commands/zone2`, `railway/speed/zone1`, `railway/speed/zone2`, `railway/zone1/signal`, `railway/zone2/signal` |
| `dashboard` | Read-only client | *(none)* | `railway/state`, `railway/events`, `railway/alerts` |
| `esp32` | IoT controller | `railway/telemetry/esp32` | `railway/commands/esp32` |

The stack intentionally keeps `allow_anonymous false` and requires a broker password file generated by `scripts/mosquitto_setup.sh`.

## ESP32 controller

The controller is an educational indicator only, never real signalling equipment. It authenticates as the `esp32` broker user and is restricted to publishing non-retained telemetry on `railway/telemetry/esp32` and reading non-retained backend commands on `railway/commands/esp32`. The backend forwards an accepted REST control only when its zone matches `ESP32_ZONE` (default: `zone1`).

1. Copy `esp32/secrets.example.h` to `esp32/secrets.h` and set the Wi-Fi credentials, device-reachable MQTT host, broker password, identity, and fixed zone. `secrets.h` is ignored by Git. Do not use `localhost`: on Wokwi or an ESP32 it means that device, not this computer.
2. With PlatformIO installed, run firmware checks from `esp32/`:

   ```bash
   pio test -e native
   pio run -e esp32dev
   ```

   The native tests cover output precedence, debounce, telemetry serialization, and command-zone validation. The `esp32dev` build uses `PubSubClient` and `ArduinoJson` declared in `platformio.ini`.
3. The firmware obtains UTC through SNTP. Until time is valid, telemetry is explicitly marked `clockValid: false` with a `null` timestamp; the backend rejects it rather than treating an epoch timestamp as fresh. It also rejects malformed, stale, duplicate, or other-zone envelope telemetry.

The output is restrictive at startup, during loss of MQTT/fresh backend context, and for active local wildlife/fault inputs. Local inputs are debounced and cannot be cleared by a received command. Reconnect and telemetry publishing are non-blocking; no old telemetry or commands are queued for replay.

The Wokwi CLI (v0.29.0) is supported in addition to the VS Code extension. It is installed at `~/.wokwi/bin/wokwi-cli`; set `WOKWI_CLI_TOKEN` from <https://wokwi.com/dashboard/ci> before running a simulation. For a cloud simulation that reaches the local broker, run `./scripts/wokwi-tunnel.sh --write-secrets` (Pinggy raw TCP), then use `scenarios/wildlife.yaml`. See `docs/wokwi-connectivity.md` for details.

The live path was verified locally through MQTT and through the cloud Wokwi
scenario over Pinggy: ESP32 detection produced `STOP`/RED, and release left the
backend in `RECOVERY_REQUIRED` until reset. Manual Stage D checklist (physical
hardware items remain **not run**):

- **PASS (Wokwi, 2026-10-21):** Boot and confirm restrictive output until current backend context arrives (`STATE COMM LOSS`).
- **PASS (Wokwi wildlife input, 2026-10-21):** Press/release `wildlife`; serial `STATE LOCAL WILDLIFE`, Godot STOP/RED and backend recovery. Physical fault input remains not run.
- **Not run (Wokwi / physical):** Issue authorized same-zone and out-of-zone dashboard controls; verify only the same-zone action reaches the controller and local faults still dominate.
- **Not run (Wokwi / physical):** Disconnect/reconnect broker or Wi-Fi while exercising inputs; verify responsiveness and a fresh telemetry publish after reconnect.
- **Not run (Wokwi / physical):** Inspect serial diagnostics and confirm no credentials are printed.

Local Docker broker success does not prove that Wokwi can reach it. Use an authenticated broker host reachable from the simulator/device; do not enable anonymous broker access as a workaround.

## Recovery and troubleshooting

- If the backend never becomes healthy, check `docker compose ps` and `docker compose logs backend mqtt web`.
- If MQTT is unavailable, regenerate the broker credentials with `./scripts/mosquitto_setup.sh` and restart the services.
- Any local secrets remain in a git-ignored `.env`; the repo stores only placeholder-only samples.
- The simulation is educational-only and is not a certified signalling system.

## Topic Contract & ACLs

The detailed contract and permission matrix are also documented in [docs/OPERATIONS.md](./docs/OPERATIONS.md).
