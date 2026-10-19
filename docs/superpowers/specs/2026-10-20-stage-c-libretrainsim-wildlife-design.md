# Stage C — Libre-TrainSim-based Godot 4.7 Wildlife Digital Twin (rewrite)

Date: 2026-10-20
Status: proposed
Parent design: [`2026-10-18-railway-digital-twin-enhancement-design.md`](./2026-10-18-railway-digital-twin-enhancement-design.md)
Related designs: [`2026-10-19-stage-a2-block-signalling-design.md`](./2026-10-19-stage-a2-block-signalling-design.md) (paused), [`2026-10-19-stage-b-dashboard-design.md`](./2026-10-19-stage-b-dashboard-design.md), [`2026-10-19-stage-d-esp32-wokwi-design.md`](./2026-10-19-stage-d-esp32-wokwi-design.md) (extended), [`2026-10-19-stage-e-integrated-delivery-design.md`](./2026-10-19-stage-e-integrated-delivery-design.md) (extended)

> **Supersedes** `2026-10-19-stage-c-godot-digital-twin-design.md`. That design
> (procedural twin, backend-authoritative trains, no wildlife/bridge) is replaced
> by this rewrite, which is based on a **Libre-TrainSim core port** and adds a
> **wildlife environment with an animal underpass** and a **graduated safety
> system**. Stage D and Stage E are extended in place (Sections 11–12).

> **Licensing:** the ported Libre-TrainSim core is **GPL v3**; the Godot project
> becomes a GPL v3 derivative. Curated third-party assets must be **CC0/CC-BY**
> with attribution in `CREDITS.md`. Non-Godot components (backend, web, ESP32
> firmware) keep their own (currently unlicensed) status and are not linked into
> the Godot binary.

> **Safety boundary:** educational simulation only. No visual, MQTT message,
> signal aspect, or braking estimate is certified railway equipment. Do not
> connect to live signalling, infrastructure, or rolling stock.

## 1. Purpose and outcome

Deliver a visually realistic **wildlife-safe railway digital twin** in Godot 4.7,
based on a ported **Libre-TrainSim** core, that:

- renders a **forest world** with a **stream, overpass bridge, and a dedicated
  wildlife underpass** beneath a **curved double-track** railway;
- runs **animated wildlife** (deer, elephant) that path-follow toward the stream,
  **prefer the underpass, but occasionally cross the rails directly**;
- runs a **graduated safety system** (warn → slow → stop → resume) driven by
  wildlife observations plus a simulated **IoT/Wokwi ESP32 sensor node**; and
- keeps realistic **local train motion** (multi-car, bogies, rotating wheels,
  cab/follow cameras) while the **backend stays authoritative for safety and
  signals**.

Stage C is complete when the project imports and runs on the installed Godot 4.7
binary at the target renderer with no script/resource errors, the LTS-based train
runs the curved track with correct wheel rotation, wildlife animates and crosses,
the safety system warns/slows/stops the train on a direct crossing and resumes on
clear, the Wokwi ESP32 node publishes sensor telemetry the backend ingests, and
the scenario director plays the safety and cinematic scenarios on the Windows GPU
demo target.

## 2. Scope and authority

### In scope

- Port the **Libre-TrainSim core runtime** (rail/track with curves, train
  movement/physics + multi-car consist, camera system, chunk loader, signal
  types) from **Godot 3.x → Godot 4.7**; ship GPL v3 `LICENSE` + `CREDITS.md`.
- Vendor a pinned **Godot-4 MQTT addon** (`goatchurchprime/godot-mqtt`, MIT) —
  not currently present in `godot/`.
- A **twin overlay** layer: MQTT bridge, safety reaction, wildlife system,
  environment/scene, scenario director.
- A **new forest world** (not Libre-TrainSim's tutorial scenes): terrain, stream,
  overpass bridge, wildlife underpass, curved double track, trees, sky.
- **Animated wildlife** (deer ×2–3, elephant ×1): skeletal walk/idle animations,
  path-following, underpass preference, occasional direct track crossing.
- **Graduated safety reaction** in the overlay (warn → slow → stop → resume).
- **Hybrid motion ownership** with a defined reconciliation contract.
- **Stage D extension**: Wokwi ESP32 node with ultrasonic + PIR + track/vibration
  sensors, status LEDs, buzzer, **servo barrier**, and an **OLED** status screen,
  over WiFi/MQTT.
- **Stage E extension**: asset hygiene, `CREDITS.md`, docs, and an end-to-end
  demo flow.
- Camera: follow + cab (+ cinematic drone), cinematic director, day/night.

### Out of scope

- Godot does **not** publish authoritative backend state: never
  `railway/state`, `railway/events`, `railway/alerts`, `railway/commands/*`,
  `railway/zoneN/signal`, or `railway/signal/*`.
- Godot does **not** call `/api/control`, `/api/speed`, or the removed
  `/api/event`.
- No certified train dynamics, braking, or photorealistic accuracy claims.
- No production TLS/provisioning (dev plaintext TCP, documented as such).
- The Libre-TrainSim **in-game editor, modding tools, scenario editor, and
  translations** are not ported.
- No claim that the wildlife underpass is a real mitigation; it is illustrative.

### Authority rules (hybrid model)

This section **replaces** the old "backend-authoritative trains" rule with the
approved hybrid contract:

- The **backend is authoritative for safety and signals**: zone hazards
  (wildlife/fault), per-zone speed limits, and (if the paused Stage A2 lands)
  block signals.
- **Godot owns local train motion** for visual realism (interpolated along the
  LTS track with correct wheel/bogie animation). This local motion is the
  rendering/simulation, not a control plane.
- **Reconciliation:** on a backend hazard or speed command, the overlay
  **overrides the local target speed** (slow or controlled stop); on `clear`, it
  resumes. The backend never has to know LTS internals — it only publishes
  hazard/speed, and Godot obeys.
- **Godot publishes permitted observation telemetry**: wildlife observations
  (feeds the backend hazard model, like the ESP32 node) and, optionally, train
  speed/position for ops/monitoring. The wildlife safety loop itself is
  **backend-self-contained** and needs no train telemetry in the backend; any
  train observation is a sensor observation and can never relax a backend
  safety decision.
- The dashboard issues all user controls through authenticated REST.

## 3. Libre-TrainSim port (Godot 3 → 4)

Source: `Libre-TrainSim-master/` (v0.9.beta1, `config_version=4`, **GPL v3**,
~812 MB — **not committed**; assets are curated/downloaded at build time).

Port only the core runtime:

| Port | Discard |
|---|---|
| Rail/track builder + curved rail segments, rail attachments, signal types | In-game editor + editor docks |
| Train: multi-car consist, bogies, wheels, brake/high-beam lights, cabs | Modding tools / `libre_trainsim_modding_tools` |
| `camera_base` (follow/cab/cinematic) | Scenario editor |
| Chunk loader (`chunk.gd`, `chunk_loader_interactive.gd`) | Translations, tutorial worlds as-is |
| Train physics/integration (speed → position along rail) | Game-specific UI/HUD not reused |

Porting notes:

- Godot 3 → 4 renames (`Spatial`→`Node3D`, `Camera`→`Camera3D`,
  `KinematicBody*`→`CharacterBody*`, `Pool*Array`→`Packed*Array`,
  `_process`/`_physics_process` signatures, signal syntax `connect("x",y)` →
  `x.connect(y)`). Scenes must be re-imported in Godot 4 (`.tscn` v3 is not
  readable by v4).
- The port lands inside `godot/` (the existing Godot 4.7 project), **not** as a
  second project; the existing procedural train/track in `main.gd` is replaced.
- A `docs/porting/` log records every changed class and why, to prove GPL
  provenance and ease review.

## 4. Architecture: LTS runtime + twin overlay

Two layers with a narrow contract:

- **LTS runtime** (`godot/addons/lts_runtime/`): the ported classes above. Exposes
  a small API surface:
  - `LTSTrain.set_target_speed_kmh(v)`, `get_speed_kmh()`, `get_track_position_m()`,
    `get_zone_id()`, `brake_to(target)`.
  - `LTSWorld.load_track(path)`, `get_track_samples()`.
  This layer is **pure simulation** — no MQTT, no safety policy.
- **Twin overlay** (`godot/src/`): owns MQTT, hazard/safety reaction, wildlife,
  environment, scenario director. It **reads** LTS state and **writes** only the
  LTS target speed (the single control entry point).

This keeps the GPL-ported core isolated from our MQTT/safety code, so the
boundary is auditable.

## 5. MQTT contract

Add-on: `goatchurchprime/godot-mqtt` (MIT, pure GDScript, TCP + user/pass).
It has **no auto-reconnect** — the overlay implements exponential backoff.

**Godot publishes (permitted observations):**

| Topic | Payload | QoS/retained |
|---|---|---|
| `railway/zoneN/wildlife` | `{zone, wildlifeDetected, species, count, timestamp}` | QoS 0 |
| `railway/trains/{id}` *(ops/monitoring only)* | `{trainId, zone, speedKmh, trackPositionM, status, timestamp}` | QoS 0 |

Godot **never** publishes `railway/state`, `railway/events`, `railway/alerts`,
`railway/commands/*`, `railway/zoneN/signal`, or `railway/signal/*` (§2). The
train-observation topic is **optional** and for ops/monitoring only — the safety
loop (§6, §9) does **not** depend on the backend ingesting it, so Stage C needs
**no backend change** to deliver the wildlife safety demo.

**Godot subscribes (consumes authoritative state):**

| Topic | Use |
|---|---|
| `railway/state` (retained) | full state; reconcile on reconnect |
| `railway/zoneN/signal` (retained) | zone signal; render |
| `railway/signal/{blockId}` (retained) | block aspects; render (only if Stage A2 lands) |
| `railway/speed/zoneN` | speed limit command → override local target |
| `railway/commands/zoneN` | hazard/clear command → safety reaction |

Reconnect: on `connect`, resubscribe and re-read retained state; never synthesise
a clear or reset from a stale snapshot.

## 6. Motion ownership and reconciliation

```
backend (authoritative: hazard, speed limit, zone signal)
   └─ publishes railway/speed/zoneN , railway/commands/zoneN , railway/state
        └─> Godot overlay (safety reaction)
              ├─ reads:  LTS local motion  (LTSTrain.get_speed_kmh / get_track_position_m)
              └─ writes: LTSTrain.set_target_speed_kmh()   (override)
```

- **Local motion** runs at LTS fidelity (accel/brake along the track); the
  overlay only changes the *target* speed, so motion stays smooth and realistic.
- **Warn:** target speed → caution limit (e.g. 30 km/h), alert flasher + buzzer.
- **Stop:** target speed → 0, controlled braking to a stand before the hazardous
  section; boom barrier lowers.
- **Resume:** on `clear`/reset, target speed restores to the zone limit.
- The safety loop is **self-contained** (wildlife/sensors → backend hazard →
  command → Godot obeys). Godot may also publish `railway/trains/{id}` so the
  backend/ops view can see the train, but this is optional and can never relax a
  backend safety decision.

## 7. Environment and world

New forest world authored in Godot 4.7 (not Libre-TrainSim's tutorial scenes):

- **Terrain**: rolling forest with a **stream** cutting through, plus a **road**
  crossing the railway over a **bridge/overpass**.
- **Wildlife underpass**: a culvert/culvert-bridge **beneath** the track connecting
  the two sides of the stream, with a walkable path and animal-friendly
  geometry.
- **Track**: curved double track (LTS rails) running through the terrain; a
  station/halt optional.
- **Vegetation**: MultiMesh trees/rocks, grass patches; PBR materials.
- **Sky/atmosphere**: HDRI or procedural sky, day/night cycle, volumetric fog.
- Assets are **CC0/CC-BY** (Sketchfab, Poly Haven) with attribution; every asset
  has a **procedural fallback** so the scene loads without downloads.

## 8. Wildlife system

- **Species**: deer (2–3) and elephant (1). Skeletal rigs with walk/idle
  animations (AnimationTree blends; IK foot placement where available).
- **Behaviour**: a path-following navigation graph from grazing areas → the
  stream, with a **decision node at the underpass**: animals **prefer the
  underpass**, but a configurable fraction **cross the rails directly** (this
  crossing is the hazard the safety system must catch).
- **Proximity/detection**: each animal has a bounding radius; the overlay
  publishes `railway/zoneN/wildlife` when an animal enters the near-track or
  on-track band.
- **Cinematic**: animals can be staged for the safety and reel scenarios.

## 9. Smart safety system (graduated)

Reuse the existing backend hazard model; the overlay enforces the reaction:

| State | Trigger | Backend | Godot reaction |
|---|---|---|---|
| Clear | no animal in any band | zone clear, normal speed limit | resume to limit |
| Warn | animal near track / ESP32 detects proximity | zone restrictive (yellow/slow aspect), caution speed limit | flashers + buzzer, target → caution |
| Stop | animal on track / sensor reports danger | zone `HAZARD`, speed 0 | controlled brake to stand, barrier lowers |
| Fault | ESP32 sensor unhealthy | zone `SENSOR_FAULT` | treat as restrictive; alert |

Exact aspect/state names come from the existing backend hazard model (Stage A);
this spec only fixes the graded behaviour and the Godot reaction per state.

The safety decision is **backend**; the overlay renders and enforces it. This does
**not** depend on the paused Stage A2 block-signalling (it uses zone hazards). If
A2 later lands, block signals render alongside and can tighten the stop point.

## 10. Camera and cinematic director

- Port LTS `camera_base`; expose **follow**, **cab**, and **drone/cinematic** modes.
- Scenario director plays: **safety scenario** (animal crosses → warn → stop →
  clear → resume), an **ops scenario**, and a **cinematic reel** (camera cuts).
- Day/night and weather toggles from the existing prototype.

## 11. Stage D extension — IoT/Wokwi ESP32 (in place)

Extend `2026-10-19-stage-d-esp32-wokwi-design.md`. The device is a **sensor node
+ local actuator**, never a control plane.

**Wokwi circuit**: ESP32 + **ultrasonic** (distance) + **PIR** (motion) +
**track/vibration** sensor + **LEDs** (safe/green, warn/amber, danger/red) +
**buzzer** + **servo barrier** + **OLED** status, over **WiFi/MQTT**.

**Topics:**

| Topic | Direction | Payload |
|---|---|---|
| `railway/telemetry/esp32` | device → broker | `{device, zone, distanceM, motion, vibration, sensorHealthy, timestamp}` |
| `railway/commands/esp32` | broker → device | `{event: WARN\|STOP\|CLEAR, ...}` |

Behaviour: publish telemetry on a fixed cadence; drive LEDs/buzzer/servo per the
latest received command using the existing freshness/staleness rules; never
mutate train state. Secrets stay in an ignored header with an example.

**Backend coupling:** the ESP32 path is **optional** for the wildlife safety
demo — the primary detection path is Godot's wildlife system publishing
`railway/zoneN/wildlife`, which the backend already ingests (no backend change).
If the new sensor fields (`distanceM`/`motion`/`vibration`) are to reach the
backend hazard model, its ESP32 telemetry validation must tolerate them; that
ingest code is currently owned by the concurrent actor, so **coordinate before
touching it**.

**Connectivity note:** Wokwi's ESP32 reaches the network via Wokwi's gateway and
can only contact endpoints reachable from the internet. A local Dockerised
Mosquitto therefore needs an **exposed endpoint or tunnel** (or a public test
broker for the Wokwi run); this is a documented setup step, not a code change.

## 12. Stage E extension — integrated delivery (in place)

Extend `2026-10-19-stage-e-integrated-delivery-design.md`:

- **Asset hygiene**: CC0/CC-BY only, `CREDITS.md`, GPL v3 `LICENSE` for the
  ported core, asset-optional fallbacks, no committed 800 MB assets.
- **Demo flow**: Wokwi node detects animal → telemetry → backend hazard → Godot
  renders wildlife crossing + safety intervention (barrier, LEDs, train stop).
- **Docs**: porting log, broker/Wokwi connectivity setup, Windows-GPU demo steps.
- **Do not touch**: `mosquitto/*`, `scripts/*`, `docker-compose.yml` unless a
  change is explicitly required and agreed.

## 13. Configuration

- `godot/config.cfg` (gitignored) + `config.cfg.sample`: broker URL, credentials,
  zone id, quality tier, camera defaults, safety thresholds (warn/stop
  distances), wildlife crossing-probability.
- Backend/ESP32 config unchanged except new topic names above.

## 14. Performance

- Forward+ as demo renderer; quality tiers (High/Medium/Low); MultiMesh
  vegetation; LOD; target ≥ 60 fps on the Windows GPU demo target.
- Headless WSL run must load and script-check even without a GPU.

## 15. Verification and acceptance

**Automated (headless):**

- Godot 4.7 headless import + script compile of the ported LTS runtime and
  overlay (no parse/resource errors).
- Scene load check (world + train + wildlife instantiate).
- MQTT integration test: broker up via Docker; Godot connects, subscribes,
  publishes observation, obeys a `railway/speed/zoneN` override.
- Wokwi firmware host tests (PlatformIO native) for sensor → LED/buzzer/servo
  precedence and staleness.
- Backend regression (`node --test`) — no regressions to A/A2/B/D/E.

**Manual (Windows GPU demo target):**

- Curved-track run with rotating wheels; follow + cab cameras.
- Wildlife walks, prefers underpass, one animal crosses directly.
- Safety sequence: warn (flasher/buzzer) → slow → stop (barrier down) → clear →
  resume. LEDs/buzzer/OLED match backend state.
- Day/night + cinematic reel play.

## 16. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Godot 3→4 port effort is large | Port core runtime only (user decision); porting log; incremental, class-by-class |
| GPL v3 applies to the Godot side | Accept (user decision); `LICENSE` + `CREDITS.md`; keep non-Godot components unlinked |
| 812 MB assets / repo bloat | Assets downloaded/curated at build time, never committed; procedural fallbacks |
| Wokwi cannot reach a local broker | Documented exposed endpoint/tunnel or public test broker; not a code change |
| Local motion vs. backend safety diverge | Single override entry point (`set_target_speed_kmh`); backend authoritative for safety; reconciliation on reconnect |
| Wildlife animation fidelity | Skeletal rigs + AnimationTree; procedural fallback if rigs unavailable |
| Paused Stage A2 (concurrent-writer collision) | Safety uses zone hazards, not blocks; A2 signals optional and additive |
| Concurrent actor on `master` (owns `esp32/**`, backend ingest, `README.md`) | Stage C core work is confined to `godot/` (untouched so far); keep the safety loop backend-self-contained (no backend change needed); coordinate before touching `esp32/**` for the Stage D extension |
