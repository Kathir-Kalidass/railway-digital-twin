# Stage C — Godot Digital Twin Design (Enhanced)

Date: 2026-10-19  
Status: proposed  
Parent design: [`2026-10-18-railway-digital-twin-enhancement-design.md`](./2026-10-18-railway-digital-twin-enhancement-design.md)  
Related designs: [`2026-10-19-stage-a2-block-signalling-design.md`](./2026-10-19-stage-a2-block-signalling-design.md), [`2026-10-19-stage-b-dashboard-design.md`](./2026-10-19-stage-b-dashboard-design.md), [`2026-10-19-stage-d-esp32-wokwi-design.md`](./2026-10-19-stage-d-esp32-wokwi-design.md), [`2026-10-19-stage-e-integrated-delivery-design.md`](./2026-10-19-stage-e-integrated-delivery-design.md)

> **Safety boundary:** This is an educational digital-twin simulation. No
> visual, MQTT message, signal aspect, or stopping-distance estimate is
> certified railway equipment. Train motion, block signalling, and braking are
> illustrative simulations only. Do not connect it to live signalling,
> infrastructure, or rolling stock.

## 1. Purpose and outcome

Deliver a visually rich, real-time Godot 4 digital twin that (a) replaces the
prototype's unauthenticated HTTP path with an authenticated MQTT client, and
(b) renders the **Stage A2 authoritative multi-train, block-signalling state**
as a realistic double-track scene with imported hero assets, advanced
animation, weather/atmosphere, and cinematic scenarios.

Godot represents the system visually and publishes simulated sensor
observations. It is **not a second control plane**: it never publishes trains,
occupancy, state, signals, commands, events, or alerts, and never calls a REST
control endpoint.

Stage C is complete when the project loads without script/resource errors at
the target renderer via the installed Godot 4.7 binary, the double-track scene
renders authoritative trains/blocks/signals, permitted telemetry publishes to
the correct zone, broker ACLs pass, reconnect reconciles from retained state
without synthetic clears/resets, and the scenario director runs the safety and
ops scenarios and the cinematic reel on the Windows GPU demo target.

## 2. Scope and authority

### In scope

- Vendor a pinned, Godot-4-compatible **MQTT client addon** and its license.
- **Forward+** rendering as the demo renderer, with a `gl_compatibility`
  fallback preset; quality tiers (High/Medium/Low).
- **Hybrid assets**: procedural deterministic world **plus curated,
  license-verified imported hero assets** (rigged rolling stock, elephant,
  deer) with skeletal **AnimationTree** blends, IK foot placement, and root
  motion.
- A **double-track ring** with blocks, a station with crossovers, tunnel,
  bridge/river, level crossing, and per-block signals, matching Stage A2.
- **Multi-train rendering** driven solely by authoritative backend state
  (interpolated, never authoritative).
- A **scenario director** with authored safety/ops scenarios and a scripted
  cinematic reel.
- Atmosphere: day/night cycle, clear/fog/rain weather, volumetric fog, PBR
  materials, post-processing.
- HUD: block/train/status panels, sync/stale/age indicators, sim disclaimer.

### Out of scope

- Godot must not publish `railway/state`, `railway/events`, `railway/alerts`,
  `railway/commands/*`, `railway/signal/*`, `railway/zoneN/signal`, or
  `railway/zoneN/train`.
- Godot must not call `/api/control`, `/api/speed`, or the removed `/api/event`.
- No claim of certified train dynamics, certified braking, or photorealistic
  accuracy.
- No production TLS/provisioning (dev uses plaintext TCP; documented as such).

### Authority rules

- Backend state, block occupancy, and retained signals are authoritative.
  Scene code must never derive or publish a more permissive aspect.
- Trains are authoritative in the backend (Stage A2); Godot interpolates
  positions between state updates for smoothness only.
- The dashboard issues all user controls through authenticated REST.
- Godot local actions are **simulator sensor inputs only** (wildlife/fault
  observations) on explicitly permitted telemetry topics; they never bypass
  backend validation/audit for user commands.

## 3. MQTT client and lifecycle

### 3.1 Addon

- Vendor **`goatchurchprime/godot-mqtt`** (MIT) under `godot/addons/mqtt/`
  with its `LICENSE` and a pinned commit recorded in
  `godot/addons/mqtt/VENDOR.md` (source URL, commit, license).
- Rationale: MIT, pure GDScript (~556 lines), no per-OS binaries (identical on
  Windows demo and WSL/headless CI), TCP + username/password + QoS 0/1 +
  retained + LWT, ships a headless test suite.
- Known gaps handled in-code: **no built-in reconnect/backoff** (implemented
  in `mqtt_bridge.gd`), **TLS uncertain** (not used; plaintext TCP).

### 3.2 Topics

| Topic | Direction | Payload/behavior |
|---|---|---|
| `railway/state` | backend → Godot | Retained expanded snapshot (Stage A2 §6); authoritative. |
| `railway/signal/{blockId}` | backend → Godot | Retained `{ block, line, zone, signal, timestamp }`. |
| `railway/zoneN/signal` | backend → Godot | Retained zone-level layered aspect (back-compat). |
| `railway/commands/zoneN` | backend → Godot | Validated command envelope (parent contract). |
| `railway/speed/zoneN` | backend → Godot | `{ zone, speedKmh, timestamp }`, `0..80`. |
| `railway/zoneN/wildlife` | Godot → backend | **Only write** for Godot: `{ wildlifeDetected, timestamp, source: "godot" }`; non-retained. |

`zoneN` ∈ {`zone1`,`zone2`}. Godot **does not** publish `railway/zoneN/train`
(removed in Stage A2). Validate topic-zone consistency, payload shape, enum
values, timestamps, and finite numeric speed before applying.

### 3.3 Startup, synchronization, recovery

- Start in `SYNCING`; never present local defaults as server-confirmed.
- Subscribe after authenticated connect; apply a valid retained `railway/state`
  snapshot atomically (validate lines/blocks/trains/zones/signals/enums and
  `updatedAt`).
- On disconnect: retain last-known state, mark stale, show offline + age; never
  publish a reset, recovery, or synthetic clear.
- Reconnect with bounded backoff + jitter, capped interval, unique client id,
  one MQTT instance, explicit unsubscribe/shutdown.
- After reconnect: resubscribe and reconcile from retained state/signals
  **before** publishing fresh wildlife observations. Never replay queued
  telemetry.
- Distinguish config errors, broker auth rejection, connection loss, malformed
  payloads, and successful sync in HUD/debug. Logs never include credentials.

## 4. Rendering and quality

- **Renderer:** `Forward+` (Vulkan) as the demo renderer; ship a
  `gl_compatibility` preset as fallback. Headless/CI uses the dummy driver for
  load/parse/contract checks only.
- **Quality tiers** (config-driven, runtime-switchable):
  - **High:** SSAO, SSIL, SSR, global illumination, volumetric fog, TAA,
    soft/PCF shadows, glow/bloom, depth of field (cinematic), AgX or ACES
    tonemap, 2× MSAA, shadow-cascades.
  - **Medium:** SSAO + shadows + glow + volumetric fog; no SSR/GI; no DOF.
  - **Low:** no GI/SSR/volumetric; simplified shadows; reduced draw distance.
- Post-processing grades per time-of-day and weather.

## 5. Asset strategy (hybrid)

- **Hero assets (imported, rigged):** locomotive + coach consist, elephant,
  deer. Skeletal rigs with `AnimationPlayer` + `AnimationTree` state machines
  (idle/walk/run/alarm/flee), IK foot placement on terrain, root motion.
- **Environment:** deterministic procedural track/terrain/vegetation (upgraded
  with PBR materials, `MultiMeshInstance3D` batching) + imported HDRI or
  dynamic sky; imported rock/foliage meshes where they raise fidelity.
- **Licensing:** only CC0/CC-BY (or equally permissive) assets. Every asset is
  recorded in `godot/assets/CREDITS.md` (name, author, source URL, license,
  modifications). No copyrighted assets. Asset selection is finalized and
  license-verified during implementation planning.
- **Asset-optional robustness:** if a hero asset is missing, a procedural
  placeholder is substituted so the project **always loads headlessly**; asset
  presence is never a hard build dependency for CI.
- **Determinism:** procedural world uses a fixed seed from config.

## 6. Scene architecture

Refactor `godot/main.gd` into a thin composition root. The MQTT addon is
accessed only through the bridge; scene nodes receive typed data/signals and
never publish/subscribe directly.

```text
godot/
├── addons/mqtt/                 # vendored addon + LICENSE + VENDOR.md
├── assets/                      # imported hero assets + CREDITS.md
├── config.cfg(.sample)          # local config; real config ignored
├── main.tscn
├── main.gd                      # composition root: build, wire, lifecycle
└── scripts/
    ├── mqtt_bridge.gd           # connect/auth/subscribe/validate/publish/reconnect
    ├── twin_state.gd            # validated authoritative snapshot + freshness
    ├── world_builder.gd         # deterministic procedural world/terrain/vegetation
    ├── track_builder.gd         # double-track ring, blocks, station, crossovers
    ├── train_controller.gd      # multi-train interpolation + rolling stock
    ├── wildlife_controller.gd   # skeletal actors, AnimationTree, scenarios
    ├── signal_renderer.gd       # per-block/zone aspect rendering (backend only)
    ├── crossing_controller.gd   # barrier + flashers
    ├── camera_director.gd       # overview/chase/cab/crossing/station + cinematic paths
    ├── scenario_director.gd     # data-driven scenario playback
    └── hud.gd                   # block/train/status panels
```

`twin_state.gd` is the only source for signal rendering and the state HUD. The
composition root owns construction, signal wiring, and cleanup.

## 7. World and topology

- **Double-track ring**: `UP` and `DOWN` lines as `Path3D` loops, each
  subdivided into ordered **block sections** matching Stage A2 block ids
  (`UP-B1`, `DOWN-B1`, …). Block boundaries render as insulated joints/markers.
- **Station** with platform blocks and a **crossover pair** (switch geometry)
  where meets/overtakes occur.
- **Feature set**: tunnel portal/interior on one line, bridge over a river,
  level crossing with boom barrier + flashers, three-aspect per-block signals,
  trackside markers, zone-boundary gantries, forest with PBR vegetation.
- **Wildlife corridors** crossing the track (elephant + deer entry points).
- Track-to-block and block-to-zone mapping is validated against `railway/state`
  at load; mismatches are surfaced, not silently ignored.
- Coach/bogie offsets stay behind the locomotive on curves; loop wrap has no
  visible teleportation.

## 8. Trains and animation

- **Multi-train rendering**: iterate `state.trains[]`; create/retire visual
  consists by id. Interpolate `block`+`offsetM` into world transforms between
  updates; label as simulated.
- **Rolling stock**: articulated bogies, couplers, brake sparks on deceleration,
  exhaust/steam, head/tail lights, speed-synced wheel rotation, suspension bob.
- **Speed/braking display**: current vs target speed, current zone/block,
  illustrative stopping-distance estimate
  (`distanceM = (speedKmh/3.6)^2 / (2*decelMps2)`), and the sim disclaimer.
  Published/displayed speed clamped to `0..80`.

## 9. Wildlife and signals

- Wildlife uses skeletal rigs with `AnimationTree` states: `idle`, `graze`,
  `approach`, `crossing`, `alarm`, `flee`, `stopped`; IK foot placement; herds
  via instancing. Enter/clear simulation inputs drive permitted telemetry; the
  backend determines hazard and authoritative aspects.
- Signals render **only** from backend state or retained signal messages
  (`railway/state` blocks, `railway/signal/{blockId}`, `railway/zoneN/signal`).
  The barrier animates restrictively for a backend-indicated hazard/fault;
  it never implies independent safety capability.

## 10. Scenarios and cinematic director

- `scenario_director.gd` plays **data-driven scenarios** (`Resource` or JSON):
  each scenario is a timed timeline of camera shots, time-of-day/weather
  presets, audio cues, and Godot-local observation triggers.
- **Scenario set:**
  - *Safety:* wildlife near-miss at dusk; sensor fault + restore;
    comm-loss + reconnect; reset/recovery.
  - *Ops:* two-train meet/pass at the station; block-signal progression;
    tunnel/bridge traverse; emergency braking (brake lights/sparks).
  - *Cinematic reel:* a scripted montage with director camera, DOF, and sound.
- **Authority caveat:** scenarios may trigger **Godot-local observations only**
  (wildlife/fault). Backend-authoritative actions (reset, speed, clear) are
  driven from the dashboard or the Stage E demo script, never from Godot.
- Audio: spatial ambience, horn, crossing bell, wheel/rail, wildlife — capped
  for performance; optional mute.

## 11. Local controls

| Input | Effect (simulation scenarios only) |
|---|---|
| Space | Toggle simulated **wildlife** observation in Zone 1 (only permitted write topic). |
| `2` | Toggle simulated **wildlife** observation in Zone 2 (only permitted write topic). |
| `C` | Cycle overview/chase/cab/crossing/station cameras. |
| `N` | Toggle day/night preset or auto cycle. |
| `W` | Cycle weather (clear/fog/rain). |
| `P` | Play/advance scenario; `Esc` stops playback. |

There is **no** local reset, speed, or sensor-fault control in Godot: the
permitted write ACL for Godot is `railway/zoneN/wildlife` only. Sensor-fault
scenarios are driven by ESP32 telemetry or by the dashboard
(`POST /api/control` with `SENSOR_FAULT` / `SENSOR_RESTORED`); Godot only
renders the resulting authoritative state. Reset, hazard clear, and speed also
come from the authenticated dashboard; Godot reflects the accepted
state/target.

## 12. Configuration

`godot/config.cfg` is local and ignored; `config.cfg.sample` documents:

| Setting | Rule |
|---|---|
| `[mqtt] host, port` | Reachable broker; host processes use a reachable address, not container-only DNS. |
| `[mqtt] username, password` | Godot broker identity; never log or commit the password. |
| `[mqtt] client_id_prefix` | Unique id generated per running instance. |
| `[simulation] zones` | Exactly `zone1`,`zone2`; validated at load. |
| `[simulation] quality` | `high`\|`medium`\|`low`. |
| `[simulation] scenario` | Optional startup scenario id. |
| `[simulation] day_night, weather` | Initial atmosphere preset. |
| `[simulation] max_publish_hz` | Wildlife publish cap (≤2 Hz heartbeat). |

The old `[network] api_base` key is removed (HTTP path retired).

## 13. Performance

- **Target:** 60 FPS @ 1080p on High on a mid-range GPU; 30 FPS floor on Low.
- **Budget:** batch repeated meshes (`MultiMeshInstance3D`), cap particles and
  shadow casters, use LOD/visibility ranges for vegetation, limit volumetric
  fog resolution, and keep per-frame allocation low.
- Record the tested machine/resolution in delivery notes; degrade gracefully to
  lower tiers rather than dropping frames.

## 14. Verification and acceptance

### Automated checks

- **Headless load/parse:** `godot --headless --editor --path godot --quit`
  with the installed Godot 4.7 binary (WSL/CI) — no script/resource errors.
- **Headless script harness:** snapshot validation, telemetry validation,
  speed clamping, zone/block mapping, and reconnect state machine.
- **Broker ACL tests:** Godot can write only `railway/zoneN/wildlife`, cannot
  write state/commands/signals/train/events/alerts, and can read permitted
  topics including `railway/signal/+`.
- **Backend integration:** Godot wildlife observations update only the intended
  zone and cannot change signal/train authority.

### Manual checklist (Windows GPU demo target)

1. Start stack + Godot; verify `SYNCING` → live after retained state.
2. Verify double track, blocks, station/crossovers, tunnel, bridge, crossing.
3. Compare trains/blocks/aspects with dashboard/backend.
4. Run safety scenarios; verify zone-isolated telemetry and braking.
5. Run ops scenarios; verify meets, block progression, emergency braking.
6. Run the cinematic reel; verify camera/DOF/audio and performance tier.
7. Stop/restart broker; verify stale/offline, no false reset, reconnect, and
   retained-state reconciliation.
8. Toggle weather/day-night; verify no runtime errors and tier knock-down.

Record unavailable checks as *not run*; never report an unexecuted Godot/hardware
check as passed.

## 15. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Godot 4.7 + addon compatibility unproven | Pure-GDScript addon (low risk); pin commit; headless load test in CI. |
| Addon lacks reconnect | Implement bounded backoff + resubscribe in `mqtt_bridge.gd`. |
| Asset licensing/sourcing blocks build | CC0/CC-BY only, `CREDITS.md`, asset-optional procedural fallback. |
| WSL cannot render Forward+ beautifully | Beauty is Windows-only; WSL does headless correctness/contract checks. |
| Visual detail hurts performance | Quality tiers, batching, caps, tier auto-knockdown; record tested spec. |
| Godot drifts toward a control plane | Enforce ACL (no train/signal/command/state writes) and code review. |
| Scenario implies safety capability | Persistent sim disclaimer in HUD, assets, docs. |
