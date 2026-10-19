# Stage C — Godot Digital Twin Design

Date: 2026-10-19  
Status: proposed  
Parent design: [`2026-10-18-railway-digital-twin-enhancement-design.md`](./2026-10-18-railway-digital-twin-enhancement-design.md)  
Related designs: [`2026-10-19-stage-b-dashboard-design.md`](./2026-10-19-stage-b-dashboard-design.md), [`2026-10-19-stage-d-esp32-wokwi-design.md`](./2026-10-19-stage-d-esp32-wokwi-design.md)

> **Safety boundary:** This is an educational digital-twin simulation. No
> visual, MQTT message, signal, or stopping-distance estimate is certified
> railway equipment. Do not connect it to live signalling, infrastructure,
> or rolling stock.

## 1. Purpose and outcome

Replace the Godot prototype's HTTP telemetry path with an authenticated MQTT
client and deliver a procedural, two-zone railway scene that follows the
backend's authoritative state. Godot represents the system visually and
publishes simulated sensor/device observations; it is not a second control
plane.

Stage C is complete when the project loads without script/resource errors,
the two-zone scene and operating states are visible, telemetry updates the
intended backend zone, broker permissions pass, and reconnect behavior
reconciles from backend state without issuing synthetic clears or resets.

## 2. Scope and authority

### In scope

- Pin and vendor a Godot 4-compatible MQTT addon and its license.
- Introduce a bridge and state model between the addon and scene components.
- Build the two-zone procedural track, train, wildlife, signals, HUD, and
  cameras, prioritizing core animation before environmental polish.
- Publish bounded-rate train occupancy/speed and wildlife observations.
- Subscribe to backend state, zone signals, command updates, and speed target
  updates.
- Show broker status, synchronization status, last-state age, and stale/offline
  state.

### Out of scope

- Godot must not call `/api/control` or `/api/speed` and must not act as an
  operator console.
- It must not publish `railway/state`, `railway/events`, `railway/alerts`,
  `railway/commands/*`, or `railway/zoneN/signal`.
- It must not reset backend state or publish a hazard clear solely from a
  local key press.
- No imported/copyrighted 3D assets, photorealism requirement, or claim of
  certified train dynamics.

### Authority rules

- Backend state and retained zone signals are authoritative. Scene code must
  not derive or publish a more permissive signal aspect.
- The dashboard issues all user controls through authenticated REST.
- Godot local actions are simulator sensor inputs only. They publish
  observations on explicitly permitted telemetry topics and do not bypass
  backend validation or audit for user commands.
- Train motion and braking are visual simulation. Local prediction is allowed
  between updates, but must reconcile to backend state and be labelled as
  simulated.

## 3. MQTT contract and lifecycle

### 3.1 Topics

Use the least-privilege ACL assignments in the parent design; do not add
`railway/#` or other broad permissions.

| Topic | Direction | Payload/behavior |
|---|---|---|
| `railway/zoneN/train` | Godot → backend | `{ trainPresent: boolean, speedKmh: number, timestamp: string, source: "godot" }`; non-retained. |
| `railway/zoneN/wildlife` | Godot → backend | `{ wildlifeDetected: boolean, timestamp: string, source: "godot" }`; non-retained. |
| `railway/state` | backend → Godot | Retained aggregate snapshot; authoritative startup/reconnect snapshot. |
| `railway/zoneN/signal` | backend → Godot | Retained `{ zone, signal, timestamp }`, signal is `GREEN`, `YELLOW`, or `RED`. |
| `railway/commands/zoneN` | backend → Godot | Validated command envelope from the parent topic contract. |
| `railway/speed/zoneN` | backend → Godot | `{ zone, speedKmh, timestamp }`; speed is finite and in `0..80`. |

`zoneN` is exactly `zone1` or `zone2`. Do not retain simulated telemetry or
commands. Validate topic-zone consistency, payload shape, enum values,
timestamps, and finite numeric speed before applying messages.

### 3.2 Startup, synchronization, and recovery

- Start in `SYNCING`; local defaults must not be presented as server-confirmed
  state.
- Subscribe after an authenticated connection and apply a valid retained
  `railway/state` snapshot atomically. Validate both zones, signal and status
  enums, speed bounds, and `updatedAt`.
- Retain last-known state on disconnect, mark it stale, and show an explicit
  offline indicator and age. Do not publish a reset, recovery, or synthetic
  sensor-clear message on reconnect.
- Use bounded reconnect backoff, capped retry interval, a unique client ID,
  one MQTT instance, and explicit unsubscribe/client shutdown.
- After reconnect, resubscribe and reconcile from retained state/signals
  before publishing fresh samples of current simulator conditions. Never
  replay queued telemetry or user commands.
- Distinguish configuration errors, broker authentication rejection,
  connection loss, malformed payloads, and successful synchronization in the
  HUD/debug output. Logs must not include credentials.

## 4. Scene architecture

Refactor `godot/main.gd` into a composition root. The MQTT addon is accessed
only through the bridge; scene nodes receive typed data/signals and do not
publish or subscribe directly.

```text
godot/
├── addons/mqtt/                 # pinned addon source and license
├── config.cfg(.sample)          # local config; real config ignored
├── main.tscn
├── main.gd                      # composition and lifecycle
└── scripts/
    ├── mqtt_bridge.gd           # connect, subscribe, validate, publish, close
    ├── twin_state.gd            # validated snapshot and freshness
    ├── telemetry_publisher.gd   # bounded-rate train/wildlife observations
    ├── world_builder.gd         # deterministic procedural world
    ├── train_controller.gd      # path following and visual speed profile
    ├── wildlife_controller.gd   # scenario and movement animation
    ├── signal_renderer.gd       # backend aspect rendering only
    ├── crossing_controller.gd   # barrier and warning visual effects
    └── camera_director.gd       # overview, chase, cab, crossing views
```

The state model is the only source for signal rendering and the state HUD.
The composition root owns construction, signal wiring, and cleanup.

## 5. World, animation, and user experience

### 5.1 Delivery priority

1. Two labelled zones, curved track, two-track geometry with documented
   track-to-zone mapping, multi-car train, wildlife crossing, three-aspect
   signals, and camera switching.
2. Zone boundary, crossing barrier/flashers, bridge and river, tunnel
   portal/interior, trackside markers, trees/terrain, and occupancy indicators.
3. Day/night cycle, weather/fog/dust, wheel motion, headlights/brake lights,
   steam, and spatial audio where performance permits.

Use deterministic procedural generation for a fixed seed. Use Godot-native
curve/path following (for example `Path3D`/`PathFollow3D`); coach offsets must
stay behind the locomotive on curves and handle loop wrap without visible
teleportation. Batch repeated meshes or use `MultiMeshInstance3D` where
needed; cap particles and environment detail to preserve responsiveness.

### 5.2 Train and braking visualization

Follow backend target-speed updates with a smooth visual acceleration and
deceleration profile. Display current simulated speed, target speed, current
zone, an illustrative stopping-distance estimate, and the simulation
disclaimer. Use the parent design's example deceleration of `1.2 m/s²`:

`distanceM = (speedKmh / 3.6)^2 / (2 * decelerationMps2)`

Clamp displayed/published speed to `0..80` km/h. A hazard, fault, or
communication loss must have a visible restrictive simulated response; no
visual response is a certified safety function.

### 5.3 Wildlife and signals

Wildlife supports `idle`, `approaching`, `crossing/on-track`, `clearing`, and
`stopped` animation states. Enter/clear simulation inputs drive telemetry;
the backend determines whether the zone is hazardous and which signal aspect
is authoritative. Render signals only from backend state or retained signal
messages. The barrier animates restrictively for a backend-indicated hazard
or fault and must not imply independent safety capability.

### 5.4 Local controls

These inputs are for simulation scenarios only:

| Input | Effect |
|---|---|
| Space | Toggle simulated wildlife observation in Zone 1. |
| `2` | Toggle simulated wildlife observation in Zone 2. |
| `F` | Toggle Zone 1 sensor-fault observation; expose an equivalent Zone 2 control in the UI. |
| Up/Down | Adjust a local-only target when no backend target is available; otherwise direct the operator to the dashboard. |
| `C` | Cycle overview, chase, driver-cab, and crossing cameras. |
| `N` | Toggle automatic day/night or a day/night preset. |

There is no local `R` reset action. Reset, hazard clear, and speed control
come from the authenticated dashboard; the accepted backend state/target is
then reflected in Godot.

## 6. Telemetry and configuration

Publish train samples on transitions and at a bounded heartbeat no more often
than 2 Hz. Publish wildlife only when the value changes. Include timestamp and
source; send finite values and only supported zones. Do not publish while
disconnected. After reconnect, publish a fresh current sample only after
state reconciliation.

`godot/config.cfg` is local and ignored. `config.cfg.sample` contains
placeholders and documents:

| Setting | Rule |
|---|---|
| MQTT host and port | Must be reachable from Godot; host processes use a reachable host address, not container-only DNS. |
| Username/password | Use the Godot broker identity; never log or commit its password. |
| Client ID | Generate unique ID per running instance. |
| Zone mapping | Exactly `zone1` and `zone2`; validate at load. |
| Publish interval | At most 2 Hz for train heartbeat, with code-side cap. |
| Speed/deceleration | `0..80` km/h and simulation-only `1.2 m/s²` example. |

## 7. Verification and acceptance

### Automated checks

- Headless Godot project load/parse check with the installed Godot 4 version,
  for example `godot --headless --editor --path godot --quit`.
- A repeatable script-level or headless contract harness verifies snapshot
  validation, telemetry validation, speed clamping, zone mapping, and
  reconnect behavior.
- Authenticated broker tests prove Godot can write only the four permitted
  train/wildlife telemetry topics and cannot write state, commands, signals,
  events, or alerts.
- Backend integration tests prove Godot telemetry updates only the intended
  zone and cannot change signal or command authority.

### Manual checklist

1. Start stack and Godot; verify `SYNCING` then live status after retained
   state is received.
2. Compare both zone states/signals with dashboard/backend.
3. Toggle wildlife in each zone and verify zone-isolated telemetry and
   dashboard/backend updates.
4. Issue hazard, clear, restore, reset, and speed actions from the dashboard;
   verify Godot follows accepted state and target updates.
5. Stop/restart the broker; verify stale/offline display, no false reset,
   reconnect, and retained-state reconciliation.
6. Confirm train/coaches, wheels, cameras, crossing effects, and day/night
   controls operate without runtime errors.

Record unavailable Godot/hardware checks as not run; do not report them as
passed. Stage C acceptance requires the project load, ACL and backend contract
tests, and manual visual/reconnect checklist to pass.
