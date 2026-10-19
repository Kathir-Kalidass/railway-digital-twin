# Railway Digital Twin — Advanced Animation & Realistic IoT Connection

**Design spec** · 2026-10-18 · Status: for review

> **Safety:** This is a classroom digital-twin simulation, not railway safety
> equipment. Signals, braking and "stopping distance" are visualizations of
> control logic. Do not connect it to real signalling, trains, or operational
> infrastructure. The backend is a trusted *control plane for the simulation*,
> not a certified safety system.

## 1. Purpose & scope

Upgrade the existing `railway-digital-twin` scaffold from a single-zone,
HTTP-telemetry prototype into a **visual, two-zone digital twin whose Godot
scene is a first-class MQTT device**, with a **trusted backend control plane**
(authentication, RBAC, validation, replay protection, audit) and a
**read-only MQTT-over-WebSocket dashboard**.

This round touches: **Godot**, the **backend**, the **dashboard**, and a
**light ESP32 topic/credential update**. It satisfies the review decisions
recorded 2026-10-18 (broker auth baseline, zone-scoped control topics, JSON
envelope, command publisher restricted to backend, maintained Godot MQTT
library, expanded verification, broker-auth validated in Stage A).

### Non-goals

- No certified railway behaviour, no real fail-safe hardware, no real
  stopping-distance claims.
- No production TLS/PKI in local dev (documented, not implemented).
- No photorealistic/imported 3D assets — visuals stay **procedural** (GDScript).
- No rework of the ESP32 into a full controller (topic/credential update only).

## 2. Goals

1. **Realistic connection:** Godot, ESP32, and dashboard are all authenticated
   broker clients; control commands flow only dashboard → REST → backend → MQTT.
2. **Visual digital twin:** two-track forest railway with curved movement,
   animated train/wildlife, dynamic 3-aspect signals, cameras, and environment.
3. **Security (Unit V):** auth, RBAC, command validation, replay protection,
   audit logging, broker authorization, documented recovery.
4. **Verifiable:** protocol, authorization, replay, fault, and reconnection
   behaviour covered by automated tests against a real Mosquitto broker.

## 3. Architecture

```
                    Mosquitto broker (TCP 1883 / WS 9001) — allow_anonymous false
                              ▲ publish / subscribe (per-client credentials + ACLs)
      ┌───────────────────────┼────────────────────────┬────────────────────────┐
  Godot twin              Backend (trusted               ESP32 node            Dashboard
  creds: godot            control plane)                 creds: esp32          creds: dashboard
  pub zone telemetry   creds: backend                   pub device telemetry  (READ-ONLY MQTT)
  sub commands/speed   pub commands/state/alerts        sub device commands   subs state/events/
                       sub telemetry/events             (zone-scoped)          alerts
                                                                               controls → REST + JWT
```

**Control path (the one that matters):** the dashboard never publishes to MQTT.
Every control action goes over **authenticated REST**, is validated and audited
by the backend, and only then does the **backend** publish to the command
topics. This is the core security property.

**Clients & permissions (enforced by `acl_file`):**

| Client | Credential | Publish | Subscribe |
|---|---|---|---|
| Godot | `godot` | `railway/zone1/train`, `railway/zone1/wildlife`, `railway/zone2/train`, `railway/zone2/wildlife` | `railway/commands/zone1`, `railway/commands/zone2`, `railway/speed/zone1`, `railway/speed/zone2`, `railway/zone1/signal`, `railway/zone2/signal` |
| ESP32 | `esp32` | `railway/telemetry/esp32` | `railway/commands/esp32` |
| Backend | `backend` | `railway/state`, `railway/events`, `railway/alerts`, `railway/zone1/signal`, `railway/zone2/signal`, `railway/commands/zone1`, `railway/commands/zone2`, `railway/commands/esp32`, `railway/speed/zone1`, `railway/speed/zone2`, `railway/security/events` | `railway/zone1/train`, `railway/zone1/wildlife`, `railway/zone2/train`, `railway/zone2/wildlife`, `railway/telemetry/esp32` |
| Dashboard | `dashboard` | *(none)* | `railway/state`, `railway/events`, `railway/alerts` |

**Signal ownership:** the backend is authoritative for `railway/zoneN/signal` (it computes the aspect and publishes it, retained); Godot only *observes* `train`/`wildlife` and *renders* the signal it is told.

Wildcard ACL entries (`railway/#`, `railway/+`) are avoided: every client lists
the exact topics it needs, and no client is granted a broad `railway/#`.

## 4. Broker security

`mosquitto/mosquitto.conf` (local dev baseline; TLS absent by design here):

```
per_listener_settings false

allow_anonymous false
password_file /mosquitto/config/password_file
acl_file      /mosquitto/config/acl_file

listener 1883 0.0.0.0
listener 9001 0.0.0.0
protocol websockets
```

- `password_file` and `acl_file` are **generated at container start** by
  `scripts/mosquitto_setup.sh` from environment/`.env` values (git-ignored).
  Credentials are **never committed**. `mosquitto_passwd -b -c` hashes them.
- ACLs are per-client and least-privilege (explicit topics per the table above);
  each client gets only its listed topics.
- The WS listener (9001) is authenticated the same as TCP; the dashboard passes
  credentials in the `mqtt.js` connection options.
- **Remote/TLS note:** for anything beyond localhost, terminate TLS/WSS, use
  `wss://`, rotate credentials via Docker secrets, and never expose 1883.
- **Wokwi caveat:** the simulator may not reach a broker on your machine's
  `localhost`. Provide a reachable, authenticated endpoint; do **not** solve
  connectivity by re-enabling anonymous access.

## 5. Topic contract

```
railway/
├── zone1/{train,wildlife,signal}
├── zone2/{train,wildlife,signal}
├── state                     (aggregate snapshot, retained)
├── events                    (accepted actions + lifecycle)
├── alerts                    (hazard/severity alerts)
├── commands/{zone1,zone2,esp32}
├── speed/{zone1,zone2}
├── telemetry/esp32
└── security/events           (rejected/denied actions)
```

**Envelope** for commands and events (consistent both directions):

```json
{
  "request_id": "b1f2c3d4-…",
  "zone": "zone1",
  "event": "WILDLIFE_DETECTED",
  "timestamp": "2026-10-18T10:00:00Z",
  "source": "godot-simulator",
  "payload": { "wildlife_detected": true }
}
```

Rules:
- Commands are **zone-scoped** so the backend authorizes/audits each
  independently.
- The backend stores processed `request_id`s (SQLite) and rejects duplicates —
  a timestamp alone does not prevent replay.
- Server validates schema, zone, source, permissions, `request_id`, and allowed
  state transition before anything is published.
- `railway/state` is **retained** so late/reconnecting clients reconcile without
  replaying stale commands.

## 6. Backend (trusted control plane)

Express, ESM, modular:

```
backend/
├── server.js            # composition + HTTP wiring
├── src/config.js        # env parsing
├── src/mqtt.js          # broker client, topic (un)subscribe, publish
├── src/auth.js          # bcrypt, JWT issue/verify, middleware
├── src/rbac.js          # role → permission map, requirePermission()
├── src/validate.js      # envelope + command schema/range validation
├── src/replay.js        # request_id registry (SQLite + in-memory LRU)
├── src/state.js         # two-zone state machine + transitions
├── src/audit.js         # SQLite audit log read/write
├── src/db.js            # better-sqlite3 init + migrations
└── src/routes/*.js      # auth, control, speed, state, events, audit, health
```

Dependencies: `express`, `cors`, `mqtt` (5.16), `better-sqlite3` (13),
`jsonwebtoken` (9), `bcryptjs` (3).

**Roles (RBAC):**

| Role | Permissions |
|---|---|
| `viewer` | read state/events/alerts |
| `operator` | viewer + issue scenario controls + speed changes |
| `admin` | operator + read audit + manage users |

**REST API:**

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/api/auth/login` | public | returns signed JWT |
| GET | `/api/me` | any | current identity/role |
| POST | `/api/control` | operator+ | scenario command (envelope in) |
| POST | `/api/speed` | operator+ | target speed for a zone |
| GET | `/api/state` | viewer+ | aggregate state (also on MQTT) |
| GET | `/api/events` | viewer+ | recent events |
| GET | `/api/audit` | admin | audit records |
| GET | `/api/health` | public | liveness + broker status |

Every protected route calls `requirePermission()`; every mutating route calls
`validate()` → `replay.check()` → `state.applyTransition()` → `audit.write()`.

**Seeded users:** `operator`/`admin` created on first boot from env passwords
(git-ignored); passwords bcrypt-hashed (cost ≥ 12). JWTs are short-lived with
expiry.

**State machine (per zone, server-authoritative):**

`NORMAL → CAUTION → HAZARD → RECOVERY_REQUIRED → NORMAL`, plus `SENSOR_FAULT`
and `COMM_LOST` (restrictive). Hazard/fault cannot be cleared by `RESET` alone —
recovery requires hazard cleared **and** sensors healthy **and** an explicit
reset issued by `operator` or `admin`. Rejected transitions are audited with a
reason.

## 7. Dashboard

React + TypeScript + Vite, `mqtt.js` over **WebSocket (ws://…:9001)** with
**read-only** `dashboard` credentials.

- Login form → JWT stored in memory; sent on REST control calls.
- Live views (push, not polling): two-zone track map, signal aspects, train
  position/speed, wildlife status, alert feed, connection status.
- **Audit / security feed** (visible to admin): accepted and rejected actions.
- Role-aware controls: `viewer` sees state only; `operator`/`admin` get controls;
  admin gets the audit view.
- Clearly displays **alerts and connection status** (offline marker on broker
  loss).

## 8. Godot digital twin

**MQTT client:** vendored [`goatchurchprime/godot-mqtt`](https://github.com/goatchurchprime/godot-mqtt)
(v1.4, MIT, pure GDScript, TCP + WS + credentials), pinned under
`godot/addons/mqtt/`. Credentials read from a git-ignored `godot/config.cfg`
(sample provided). No hand-rolled protocol code.

**Scripts (split from `main.gd`):**

```
godot/
├── addons/mqtt/            # vendored MIT addon
├── config.cfg(.sample)
├── main.gd                 # composition
├── scripts/mqtt_bridge.gd  # wrap addon: publish zone telemetry, subscribe cmds/speed
├── scripts/sim_state.gd    # local mirror of server state + braking model
├── scripts/world_builder.gd
├── scripts/train.gd
├── scripts/wildlife.gd
├── scripts/signals.gd
└── scripts/camera_director.gd
```

**Track & environment** (procedural): two parallel tracks; S-curves; a
left-hand and right-hand junction with animated switch points; an elevated
bridge over a river with pillars/railings + animated water; a tunnel section
with interior headlight illumination and entry/exit occupancy sensors; trackside
infrastructure (sleepers, ballast, catenary poles, km markers, signal posts).
Curved movement via `Path3D`/`PathFollow3D` with coaches articulating on curves.

**Train animation:** speed-proportional **wheel rotation**, coach articulation,
gradual **acceleration** and **braking** (v²/2a stopping-distance model shown in
the HUD), **headlight** (spotlight + beam, lights the tunnel), **brake lights**
during simulated emergency braking, horn/engine/wheel/brake audio
(`AudioStreamPlayer3D`).

**Wildlife:** elephant with `AnimationPlayer`/`AnimationTree` walk/turn/stop/
cross cycles that moves between forest and detection zones; optional deer
variant. Scenario set: approaching → on track → herd crossing → leaving danger
zone → returning while train approaches. Zone entry via `Area3D`; forward
detection via `RayCast3D`.

**Signals & safety effects:** animated 3-aspect heads driven **by the safety
controller, not decoration**; flashing warning lights, animated level-crossing
barriers, wildlife beacons, pulsing danger-zone outline, on-animal alert
markers, occupancy indicators, signal transitions. Sensor failure / comm loss
display a fault warning and apply the defined restrictive state.

**Cameras:** cinematic follow, control-room overview (both tracks + all state),
driver viewpoint; optional depth-of-field/fog/motion blur; short slow-motion
replay on intrusion. `Camera3D` + a director.

**Environment life:** wind-swayed trees (`MultiMeshInstance3D` for forests/grass),
drifting fog, day/night lighting, `GPUParticles3D` dust/smoke/rain.

**Digital-twin ↔ IoT mapping (authoritative logic stays in the backend):**

| Sim event | Sim response | MQTT |
|---|---|---|
| Train enters zone | occupancy changes | publish `zoneN/train` |
| Wildlife detected | marker + warning zone | publish `zoneN/wildlife` |
| Hazard confirmed | signal restrictive | publish `zoneN/signal` |
| Braking initiated | speed decreases | publish speed telemetry |
| Sensor failure | fault indicator | publish sensor-health alert |
| MQTT disconnect | network indicator | record comm fault |
| Hazard clears | recovery animation | require valid recovery |
| Train stops | speed zero | publish stopped state |

**Visual delivery phases** (per the stated priority):
1. Curved-track movement, two-track geometry, train + elephant animation,
   dynamic signals, camera switching.
2. Weather, day/night, terrain detail, environmental effects.
3. Audio, slow-motion replay, finishing polish.

## 9. ESP32 (light update)

Keep the firmware; update to **device-specific credentials** (`secrets.h`,
git-ignored), subscribe `railway/commands/esp32`, publish
`railway/telemetry/esp32` using the shared envelope; retain signal-aspect,
buzzer, sensor-input and fault-telemetry behaviour. Update `diagram.json` and
`libraries.txt` accordingly.

## 10. Data model (SQLite)

- `users(id, username, password_hash, role, created_at)`
- `processed_requests(request_id PK, username, received_at)` — replay registry
- `audit(id, time, actor, role, action, zone, target, result, reason, source)`

## 11. Verification plan

Automated (`node:test`) against a real Mosquitto in Docker + the backend. Run
with `npm test`; Stage A must pass broker-auth + connectivity before later
stages.

| # | Test | Expected |
|---|---|---|
| 1 | Login valid | JWT issued |
| 2 | Control without token | 401 rejected |
| 3 | `viewer` issues control | 403 forbidden + audited |
| 4 | Invalid speed / malformed payload | 400 rejected |
| 5 | Duplicate `request_id` | rejected, no second action |
| 6 | Dashboard publishes MQTT command | broker denies (ACL) |
| 7 | Godot creds publish `railway/state` | broker denies (ACL) |
| 8 | Wildlife in zone1 | zone1 RED; zone2 YELLOW caution (zone2 wildlife flag stays false) |
| 9 | Wildlife in zone2 | zone2 responds independently |
| 10 | Sensor failure / MQTT disconnect | fault visible; recovery policy applied |
| 11 | MQTT reconnect | state reconciled, no stale command replay |
| 12 | `/api/audit` as non-admin | 403 |
| 13 | State publish is retained | late subscriber receives snapshot |

**Not testable in this environment:** the Godot scene/MQTT addon (Godot is not
installed). Deliver a manual checklist plus
`godot --headless --check-only` / run instructions. Web app verified via
`tsc` + `vite build`.

## 12. Delivery stages

- **A — Backend foundation:** Express, auth/RBAC, SQLite audit + replay,
  two-zone state machine, MQTT bridge, **broker auth + ACLs + connectivity
  validated here**, automated tests. See the Stage A implementation plan:
  [`2026-10-18-stage-a-backend-foundation.md`](../plans/2026-10-18-stage-a-backend-foundation.md).
- **B — Dashboard:** login, role-aware controls (via REST), MQTT-over-WS
  read-only live updates, two-zone visualization, audit feed. See
  [`2026-10-19-stage-b-dashboard-design.md`](./2026-10-19-stage-b-dashboard-design.md).
- **C — Godot:** vendored MQTT addon + bridge, procedural two-track world,
  train/wildlife animation, braking dynamics, signals, cameras.
- **D — ESP32/Wokwi:** per-client credentials, device-scoped topics, fault
  telemetry.
- **E — Delivery:** Docker/env setup, test scripts, demo scenarios, architecture
  diagram, limitations doc.

Stages C–E have separate detailed designs:
[`Stage C — Godot`](./2026-10-19-stage-c-godot-digital-twin-design.md),
[`Stage D — ESP32/Wokwi`](./2026-10-19-stage-d-esp32-wokwi-design.md), and
[`Stage E — Integrated delivery`](./2026-10-19-stage-e-integrated-delivery-design.md).
Each stage is planned and verified before the next; Stage A first.

## 13. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Godot MQTT addon untested here | Pin version, vendored; contract covered by Node harness; manual Godot checklist |
| Wokwi network reachability | Test early in Stage D; reachable authenticated broker; never re-enable anonymous |
| `better-sqlite3` native build in Docker | Node 24 base + prebuilds; verified in Stage A |
| Broker auth + ACL friction across 4 clients | Explicit config + generated password file + per-client ACL tests |
| Scope of animation wishlist | Phased visual delivery (§8), MVP visual first |

## 14. Open decisions

- Default dev credentials & password source (`.env` vs Docker secrets) — propose
  `.env` for dev, secrets for anything else.
- Whether the dashboard also needs a zone-scoped speed control per track, or one
  global speed — propose per-zone (`railway/speed/zoneN`).
