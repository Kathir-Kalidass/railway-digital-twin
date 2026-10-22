# Stage E acceptance record

Date: 2026-10-22
Host: Linux (WSL, headless), Godot 4.7.2, PlatformIO, Node.js 24.

Educational simulation only; not certified railway equipment.

## Automated gate

| Surface | Command | Result |
|---|---|---|
| Godot headless | `bash godot/tests/run_tests.sh` | PASS (34 suites) |
| ESP32 host logic | `cd esp32 && pio test -e native` | PASS (15 cases) |
| Backend | `MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test` (isolated broker) | PASS (106 tests) |
| Web build | `cd web && npm run build` | PASS |
| ESP32 firmware | `cd esp32 && pio run -e esp32dev` | PASS (1.1 MB image, 87.1% flash) |

Latest rerun (2026-10-23): Godot 39/39, backend 118/118, ESP32 native
15/15, web build PASS. The gate now includes `test_wrong_line_visual` and
`test_wrong_line_hud`.

Godot suites (34): `test_camera_director`, `test_catenary_double`,
`test_corridor_flatten`, `test_crossover_visual`, `test_e2e_safety`,
`test_esp32_integration`, `test_fleet_controller`, `test_fleet_hud`, `test_hud`,
`test_level_crossing_two_track`, `test_lts_full_enhance`, `test_meet_hud`, `test_meet_scenario`,
`test_mqtt_bridge`, `test_onboard_braking`, `test_onboard_camera`, `test_onboard_detector`,
`test_parse`, `test_port_helpers`, `test_real_assets`,
`test_river_bridges`, `test_scenario_director`, `test_scene_load`,
`test_sensor_huts`, `test_signal_masts`, `test_station_crossovers`, `test_station_island`,
`test_track_registry`, `test_train_loop`, `test_train_reconciler`,
`test_wildlife_director`, `test_wildlife_dual_track`, `test_wildlife_publisher`, `test_wildlife_safety`.

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
- Backend tests need a broker for the ACL/e2e cases. With the host broker
  unavailable they run against a disposable container on 1884:
  `docker run -d --rm --name rdt-test-mqtt -p 127.0.0.1:1884:1883
  -v "$PWD/mosquitto:/mosquitto/config:ro" eclipse-mosquitto:2`, then
  `MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test`. The suite uses
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

Deferred by the approved phased scope: wildlife-underpass preference and the
Phase 2 visual slices. The Phase 2 design is recorded separately.

## Stage 2A backend-live verification (2026-10-21)

Slice 2A is implemented on branch `master`. The backend is authoritative for two
trains (`T1` UP, `T3` DOWN), ten blocks, per-block aspects, station dwell state,
and one station crossover pair (`UP-B2 <-> DOWN-B2`).

| Item | Evidence |
|---|---|
| Two-train fleet state | `state.test.js` exposes `trains`, `lines`, `blocks`, `station`, `routes`; `config.test.js` asserts `T1`/`T3`, `753.9822 m` UP, `728.8495 m` DOWN |
| Per-block aspects and retained MQTT signals | `signalling.test.js`, `bus.test.js`; `bus.snapshot()` publishes retained `railway/signal/{blockId}` |
| Occupancy safety | `simulation.test.js` holds a train at the boundary of a RED block, and lets it continue past a RED block occupied by its own overlapping consist (`f55f872`); `routes.js` rejects occupied crossover destinations |
| Crossover interlock | `routes.test.js` grants one route at a time, rejects hazards/occupancy, releases after clear; `POST /api/route` audited with `route:set` RBAC |
| Fixed-timestep loop | `loop.test.js` ticks `state` and publishes a snapshot; `server.js` starts the loop on MQTT connect and stops it on close |
| ACL least privilege | `broker_acl.test.js`; godot reads `railway/state` and `railway/signal/+` and can no longer write `railway/zoneN/train`; esp32 cannot read block signals |
| Legacy endpoint removed | `POST /api/event` returns 404 (`control_routes.test.js`); `/api/speed` accepts `trainId` and rejects unknown IDs |
| Live server check | `node backend/server.js` on the isolated broker published `railway/state` at 2 Hz with `T1`/`T3` moving and retained per-block signals for `UP-B0`/`DOWN-B0` |
| Live crossover grant | With `T3` held via `/api/speed`, `POST /api/route` (`X-UP-DOWN`) returned the active route and moved `T1` from `UP-B2` to `DOWN-B2`; the same request while `T3` occupied the destination correctly returned 409 |
| Regression | Backend 84/84, Godot 16/16, ESP32 native 14/14, `pio run -e esp32dev` PASS, `web` build PASS |

The legacy `snapshot().train` summary is retained for un-migrated clients. Godot
and ESP32 integrations still pass unchanged; visual double-track rendering and
meet/pass remain in slices 2B–2E.

## Stage 2B double-track world verification (2026-10-22)

The twin renders two concentric loops (UP radius 120 m, DOWN radius 116 m,
4.0 m spacing), an island station inside backend block `B2`, the visible
station crossover pair, widened river bridges, and a two-track level crossing.

| Item | Evidence |
|---|---|
| Inner loop + registry | `test_track_registry.gd`: DOWN radius/length/offset, 4 m spacing at four angles, `TrackRegistry` maps both lines |
| Corridor | `test_corridor_flatten.gd`: both centre lines and the mid-corridor are flatten sources, the corridor ends 12 m outside the outer rail; river still carved |
| River bridges | `test_river_bridges.gd`: one 12 m deck per river crossing covers both centre lines; piers clear both rails |
| Level crossing | `test_level_crossing_two_track.gd`: two crossing points, pad covers both tracks, both barrier sets (2 pivots) stand clear of both tracks and lower together |
| Island station | `test_station_island.gd`: five identical 9.6 × 1.8 × 2.2 m modules centred between the rails inside `UP-B2`/`DOWN-B2`, tops level at +0.55 m, benches/bins on the deck (`2B.1`); captures `platform_after_topdown.png`, `platform_after_oblique.png` |
| Crossovers | `test_station_crossovers.gd`: `CrossoverA` (UP 312 m) and `CrossoverB` (UP 434 m) end on both centre lines, switch blades present |
| Catenary + trees | `test_catenary_double.gd`: wire runs above both lines; no tree within 5 m of either centre line |
| Regression | Godot 22/22, backend 84/84, ESP32 native 14/14, `pio run -e esp32dev` PASS |
| Capture | `/tmp/opencode/double_track_overview.png` (double-track overview) |

## Stage 2F distributed wildlife sensing & onboard vision verification (2026-10-22)

Stage 2F is fully implemented across the stack: distributed trackside sensing (10 huts),
per-train forward simulated-ML camera detection with zero-latency local braking,
backend dual-evidence block hazard fusion, ESP32 edge command forwarding, and
deterministic proximity animal appearance scenarios.

| Item | Evidence |
|---|---|
| Stopping-distance model | `test_onboard_braking.gd` PASS: pure quadratic stopping distance $d_{\text{stop}}(v) = v \cdot t + \frac{v^2}{2a} + d_{\text{margin}}$ (56 m at 36 km/h) and safe-speed limit inversion |
| Lead carriage forward camera | `test_onboard_camera.gd` PASS: camera forward vector aligns with carriage forward tangent ($\text{dot} > 0.98$) across straight track and multiple curve apexes |
| Simulated ML camera detector | `test_onboard_detector.gd` PASS: forward cone vision (±25° horiz, ±10° vert, 180 m range), confidence scoring (deer 0.9, elephant 1.1), analytic occlusion against terrain hill, tree trunks, and bridge decks; critical detection invokes `set_local_wildlife_limit(0)` with MQTT offline |
| Distributed trackside huts | `test_sensor_huts.gd` PASS: 10 huts (`UP-S0`..`UP-S4`, `DOWN-S0`..`DOWN-S4`) with 75 m overlapping radius, status lamps, and observation publishing to `railway/wildlife` |
| Deterministic wildlife director | `test_wildlife_director.gd` PASS: seed 20261022 produces identical sequence of `(trainId, distanceM, species, count)` 80–280 m ahead with 30–60 s cooldown; HUD renders `CAM clear` / `CAM detect` |
| Backend block hazard & dual evidence | `test/wildlife_observation.test.js` PASS: observation validation, separate `trackside` and `onboard` evidence slots, block RED, approach YELLOW, opposite line unaffected, crossover rejected during hazard, clearing requires recovery + reset |
| ESP32 edge alert forwarding | `test/wildlife_observation.test.js` and `esp32/test/test_logic/test_logic.cpp` PASS: edge-triggered `WILDLIFE_DETECTED` / `WILDLIFE_CLEARED` forwarded to `railway/commands/esp32` with `source: "backend"`, accepted by ESP32 firmware |
| Web dashboard evidence badges | `web/src/App.tsx` and `web/src/style.css` compile cleanly with Vite; renders `CAM` / `HUT` hazard tags on block diagram |
| Full suite regression | Godot 33/33 PASS, Backend 77/77 unit tests PASS, ESP32 native 15/15 PASS, Web build PASS |

## Stage 2G chance-based meet crossover verification (2026-10-22)

Stage 2G replaces the fixed scripted meet with a backend-authoritative seeded
meet scheduler. Holds use `commandedSpeedKmh = 0` on the authoritative train;
crossovers are granted only through `routes.requestRoute` (occupancy, hazard,
and restrictive-zone checks unchanged).

| Item | Evidence |
|---|---|
| Seeded PRNG | `test/rng.test.js` PASS: same seed reproduces the sequence, different seeds diverge, values stay in range |
| Meet scheduler | `test/meets.test.js` PASS: hold while the other train moves, hold release only after expiry/hazard clear, disabled mode inert, trigger arms the next window |
| Crossover safety | `test/meets.test.js` PASS: valid station route only, interlock rejections retried then skipped as `SAFETY_HELD`, completion after route release |
| Reproducibility | `test/meets.test.js` PASS: identical history for the same seed, different history for another seed |
| REST control | `test/control_routes.test.js` PASS: `/api/meet` auth/RBAC/validation/replay/audit; seed applied to the live snapshot |
| Godot HUD | `test_meet_hud.gd` PASS: phase, holder, route and next-meet countdown; absent `meets` tolerated |
| Web dashboard | `web/src/App.tsx` meet card builds cleanly |
| Capture | `/tmp/opencode/meet_randomized.png` (station meet with two trains and active crossover) |

## Stage 2E integrated delivery verification (2026-10-22)

Stage C2 is complete across slices 2A-2G. This pass re-ran the integrated gate
after 2F (distributed wildlife sensing) and 2G (chance-based meet crossover).

| Item | Evidence |
|---|---|
| Full automated gate | Godot 34/34 PASS; backend 106/106 PASS against the isolated Mosquitto on 1884; ESP32 native 15/15 PASS; `pio run -e esp32dev` PASS (87.1% flash); web build PASS |
| Wildlife affects both lines | `test_wildlife_dual_track.gd` holds T1 and T3 target speed at 0 km/h on a crossing hazard; backend `wildlife_observation.test.js` verifies block RED, approach YELLOW, and opposite-line independence |
| Dashboard integration | Multi-train cards, per-block occupancy/aspects, per-train speed control, evidence badges, and the 2G meet card; `npm --prefix web run build` clean |
| ESP32 unaffected | Native suite 15/15 and firmware build PASS; a live trackside observation produced `railway/commands/esp32` `WILDLIFE_DETECTED` with `source: backend` |
| Live integrated smoke | Broker 1884 + backend 3101: `/api/health` connected; state listed both trains; `POST /api/meet {seed: 4242, trigger: true}` returned seed 4242, and a station window held T3 (`commandedSpeedKmh=0`, 48 to 0 km/h) then recorded `HELD`; a trackside observation on `UP-B2` set `overall=HAZARD` with `UP-B2 RED`; clearing it left `RECOVERY_REQUIRED`; `POST /api/control RESET zone1` restored `NORMAL`; retained `railway/state` showed 2 trains and meet seed 4242 |
| Captures | `/tmp/opencode/double_track_overview.png`, `/tmp/opencode/platform_after_topdown.png`, `/tmp/opencode/platform_after_oblique.png`, `/tmp/opencode/meet_randomized.png` |

Post-gate fix (2026-10-22): backend-driven crossovers now blend the visible
consist between tracks instead of snapping, and `test_crossover_visual.gd`
asserts smooth carriage movement with no apply-state jump. Evidence:
`/tmp/opencode/crossover.gif` plus `crossover_before/midway/after.png`.

Environment note: the host `mosquitto` service occupies `127.0.0.1:1883`, so
`godot/tests/regress.sh`'s compose-broker step is shadowed and its ACL tests
fail in this environment. The gates above were run with the documented isolated
broker (`-p 127.0.0.1:1884:1883`, `MQTT_URL=mqtt://127.0.0.1:1884`); the 1883
path is unchanged for environments without the host broker.

## Manual demo

The Windows GPU checklist is `docs/demo-windows.md`. The visual subset was
exercised on the WSLg D3D12 GPU path on 2026-10-21. The local ESP32→backend→
Godot path and the cloud Wokwi scene were exercised through MQTT; the Windows
host run is still required for the dashboard and physical-hardware checks.

## Regenerate

```bash
bash godot/tests/regress.sh; echo "exit=$?"
```

## Stadium Phase 1 verification (2026-10-22)

The UP and DOWN loops now share a 250 m straight-sided stadium footprint
(centre `z = ±120 m`, straights `x = -125..125 m`, east/west 120 m curves),
with the island station and interlocked crossovers A/B on the south straight.
DOWN runs operational chainage opposite physical chainage; T1 is clockwise and
T3 anticlockwise.

| Item | Evidence |
|---|---|
| Stadium geometry and inverse chainage | `test_stadium_track.gd`, `test_geometry.test.js`; UP 1253.9822 m, DOWN 1228.8495 m, block lengths 250.796 / 245.77 m |
| Station and crossovers | `test_station_crossovers.gd`, `test_station_island.gd`; platform 150–198 m, X-A at 120 m, X-B at 240 m |
| Opposite running | `test_opposite_running.gd`; T3 faces west on the south straight, moves anticlockwise, camera aligns with travel |
| Wildlife chainage | `test_sensor_huts.gd`, `test_onboard_detector.gd`, `test_wildlife_director.gd`; DOWN operational conversion and behind-train spawning |
| Automated gate | Godot 36/36 PASS; backend 109/109 PASS (isolated broker); ESP32 native 15/15 PASS; web build PASS |
| Captures | `/tmp/opencode/double_track_overview.png`, `platform_after_topdown.png`, `platform_after_oblique.png`, `meet_randomized.png`, `crossover_before.png`, `crossover_after.png` |

Visual acceptance: the overview shows the stadium outline and river crossings;
the station captures show the island platform, canopy, station building and both
tracks; T1/T3 render in opposing orientations; the crossover capture follows a
train across the station connection.

## Stadium Phase 2 wrong-line verification (2026-10-23)

The operator can request an interlocked wrong-line run from the dashboard. The
requested train crosses from UP to DOWN at A, runs against normal traffic, and
crosses back at B; the opposing train holds at the configured point outside B.
Meets are separate station holds and no longer request a crossover.

| Item | Evidence |
|---|---|
| Wrong-line state/API | `backend/test/wrong_line.test.js`, `wrong_line_api.test.js`, `state.test.js`; GET/POST/cancel endpoints, RBAC, replay and audit; phases `APPROACH → CROSS_ENTRY → WRONG_LINE → CROSS_EXIT → CLEARANCE → DONE` |
| Opposing hold point | `wrong_line.test.js` asserts the opponent keeps running while far from the hold and commands 0 only inside braking distance |
| Live hold at B | Broker 1884 + backend 3101: request `WL-T1-1` held T3 at `holdPhysicalM=320`; T3 decelerated from 48 km/h and settled at physical 320.1 m, then released when T1 completed clearance |
| Godot route animation | `test_wrong_line_visual.gd`: T3 stays visible on DOWN while T1 blends through A, no position snap, blades A/B activate and clear, T1 returns to UP |
| HUD | `test_wrong_line_hud.gd`: `WRONG-LINE T1 <phase> <pct>% T3 HOLD` from backend route state |
| Hold-only meets | `meets.test.js`: no crossover request, holder releases with outcome `HELD`; `config.meets.crossoverChance = 0` |
| Web operator UI | `web/src/App.tsx` login/token, wrong-line eligibility panel, start/cancel, `/api/control` envelope; `npm --prefix web run build` PASS |
| Automated gate | Godot 39/39 PASS; backend 118/118 PASS (isolated broker); ESP32 native 15/15 PASS; web build PASS |
| Captures | `/tmp/opencode/wrong_line_before.png`, `wrong_line_midway.png`, `wrong_line_after.png` at 1440×900; numbered frames `wrong_line_frame_00..35.png` |

Repeatable live scenario: T1 starts at UP physical 0 and T3 starts on DOWN-B3 at
physical 420 m, about 100 m before the hold point. Requesting the wrong line as
soon as the backend is healthy makes both trains visible near the station while
T1 runs through the route.

Regenerate captures:

```bash
xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 \
  --path godot --resolution 1440x900 --rendering-method gl_compatibility \
  --script res://tests/capture_crossover.gd
```

## Stadium Phase 3 camera/ML/near-animal verification (2026-10-23)

Phase 3 completes the staged `NONE → SUSPECTED (30 km/h) → CONFIRMED (0
km/h)` chain with backend-authoritative confirmation, camera evidence, a
two-stage near warning, and operator re-arm. The stadium layout, opposite
running and wrong-line hold/reservation evidence are recorded in the Phase 1
and Phase 2 sections above.

| Item | Evidence |
|---|---|
| Staged hazards and aspects | `wildlife_observation.test.js`: trackside `SUSPECTED` makes an unoccupied hazard block `YELLOW`; camera confirmation makes it `RED`; clearing evidence leaves a confirmed block latched |
| Camera ingest | `camera.test.js`: bearer token, `X-Captured-At` freshness, duplicate event id, two-frame confirmation, and ML-degraded response |
| Near vs confirmed policy | `near_animal.test.js` 9/9: one camera frame → `SUSPECTED`/30 km/h and one `WILDLIFE_NEAR`; second frame → `CONFIRMED`/0 and `WILDLIFE_DETECTED`; clear never downgrades confirmed; duplicate event ids are ignored; ESP32 delivery is not required for the backend stop; RESET keeps the train at 0 until `/api/speed` |
| Camera target block | `test_camera_confirmation.gd`: a hazard in `UP-B1` while the train is in `UP-B0` uploads `X-Block: UP-B1`, not the train's block |
| Godot near warning | `test_near_animal_warning.gd`: first detection limits to 30 km/h, second confirms 0, clear resets, duplicate detections do not republish; `test_onboard_detector.gd` still passes |
| ESP32 near output | `esp32/test/test_logic/test_logic.cpp` 16/16: `WILDLIFE_NEAR` → `WARNING`, `ANIMAL NEAR`, buzzer pulse; `RESET` clears both flags |
| Web operator surface | `web/src/App.tsx` camera health + staged hazard/evidence panel; `npm --prefix web run build` PASS |
| Live near → confirmation | Broker 1884 + backend 3101 + ML stub 8001: trackside `UP-B0` observation → `SUSPECTED`, zone1 `YELLOW`, T1 target 30 km/h, ESP32 `WILDLIFE_NEAR`; two JPEG frames → `SUSPECTED` then `CONFIRMED` elephant 0.92, T1 target 0, ESP32 `WILDLIFE_DETECTED` |
| Live evidence | `backend/data/camera-evidence/final-frame-2.jpg` (23,291 bytes) written from the confirming frame |
| Live latch and reset | Clearing the trackside sensor left `CONFIRMED` with `sensorSources: []` and T1 at 0; `RESET zone1` returned zone1 to `NORMAL` with no hazard, sent `RESET` to ESP32, and kept T1 at `commandedSpeedKmh: 0` until `/api/speed` set 48 |
| Live aspect nuance | While T1 occupied `UP-B0`, that block stayed `RED`; the zone1 signal showed `YELLOW` for `SUSPECTED`. Unoccupied hazard blocks are covered as `YELLOW` by `wildlife_observation.test.js` |
| Real-model smoke | Skipped: no model weights were cached; the stub ML service returned elephant 0.92 with `modelLoaded: true`. No weights are committed |
| Automated gate | Backend 137/137 PASS (isolated broker); Godot 41/41 PASS; ML 5/5 PASS; ESP32 native 16/16 PASS; `pio run -e esp32dev` SUCCESS (RAM 15.5%, Flash 87.1%); `web` build PASS |
| Captures | `/tmp/opencode/camera_confirm.png` at 1440×900 shows the confirmed HUD, train, and elephant ahead; `/tmp/opencode/double_track_overview.png`, `wrong_line_before.png`, `wrong_line_midway.png`, `wrong_line_after.png` cover stadium and wrong-line views |

Regenerate the camera-confirm capture:

```bash
xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 \
  --path godot --resolution 1440x900 --rendering-method gl_compatibility \
  --script res://tests/capture_camera_confirm.gd
```
