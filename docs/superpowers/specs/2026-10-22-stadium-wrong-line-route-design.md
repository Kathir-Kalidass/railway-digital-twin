# Stadium Double Track, Interlocked Wrong-Line Route, and Camera-Confirmed Wildlife Stop — Design

**Date:** 2026-10-22
**Status:** Approved design, amended with camera confirmation, ready for implementation planning
**Supersedes:** the circular-loop assumptions in the 2G meet crossover design only where described below.

## 1. Purpose

Replace the small circular test loop with a realistic stadium-shaped double-track
railway, run one train in each direction, let an operator perform a prototypical
wrong-line movement, and add a two-stage wildlife safety chain:

1. T1 crosses from UP to DOWN at Crossover A.
2. T1 runs against DOWN traffic through the single-line section.
3. T1 crosses back to UP at Crossover B.
4. T3 is held outside the section until T1 and its whole train have cleared.
5. A trackside or onboard sensor detects an animal and slows the train.
6. The train's forward camera captures real frames; an ML service confirms the
   animal and stops the train.

The change is split into three implementation milestones:

- **Phase 1 — Stadium + opposite running:** track geometry, chainage, block
  layout, direction-aware rendering, wildlife chainage compatibility.
- **Phase 2 — Wrong-line route + operator UI:** interlocking, holds, phases,
  API, Godot HUD, web control, captures.
- **Phase 3 — Sensor-slow, camera-confirm, stop:** sensor suspicion, real camera
  frames, ML inference service, staged hazard/aspects, HUD/web evidence.

## 2. Current State and Problems

- `Track` and `InnerTrack` are concentric circles (`radius` 120 m and 116 m),
  so both trains travel the same rotational direction.
- Backend `direction` is metadata only; `stepTrains` always advances block
  indices forward (`backend/src/simulation.js`).
- Crossovers are abstract block jumps: `requestRoute` moves a train to the
  destination block at offset 0 (`backend/src/routes.js`), not to a physical
  turnout.
- The 2G meet crossover teleports the holder; it does not model a real
  single-line movement.
- Downstream wildlife distances assume a single physical direction on both
  lines.
- The loop is too small and visibly circular for a believable main-line
  demonstration.
- The existing "onboard camera" is geometric: it checks ranges and cones, never
  image pixels. No ML model or camera confirmation exists.

## 3. Goals

- A closed stadium loop with long straights and 180° end curves; continuous,
  infinite running with no teleport at the seam.
- Visibly opposite train movement: T1 clockwise, T3 anticlockwise.
- A station, platform, and crossover pair on the south straight.
- An operator-commanded, interlocked wrong-line run with realistic holds,
  reservations, hazard checks, and audit.
- State-driven crossover animation that never freezes or snaps the train.
- Web and Godot status for eligibility, phase, progress, and held traffic.
- A two-stage wildlife response: sensor detection slows the train; real camera
  frames plus ML confirmation stops it.
- Camera evidence, confidence, and model metadata visible in the HUD and web.
- All existing functionality (meets, wildlife, ESP32, web) remains green.

## 4. Non-Goals

- Full bidirectional block signalling for arbitrary wrong-line movements.
- ESP32-CAM hardware integration, model training/fine-tuning, or cloud video
  streaming.
- Multi-train (>2) scheduling or a general timetable.
- New ESP32 firmware behaviour beyond the existing sensor and alert path.
- Replacing the existing MQTT/REST architecture.

## 5. Stadium Layout

### 5.1 Geometry

Two straights of `S = 250 m`, joined by 180° curves:

- UP (outer): `R = 120 m`, `L_up = 2S + 2πR = 1253.9822 m`.
- DOWN (inner): `R = 116 m`, `L_down = 2S + 2πR = 1228.8495 m`.
- Track spacing: 4 m.
- Footprint: approximately 490 m × 240 m.

Both tracks are centred on the world origin and share the same chainage
starting point. Local chainage runs, in order:

1. `0 … 250` — south straight, heading +X.
2. `250 … 250 + πR` — east semicircle.
3. `250 + πR … 500 + πR` — north straight, heading −X.
4. `500 + πR … 2S + 2πR` — west semicircle back to the start.

The path is closed and sampled analytically; `fposmod` handles the seam so a
train crossing the loop start has no visual step.

### 5.2 Track implementation

`LTSTrack` keeps its current public API (`length`,
`get_global_transform_at_distance`, `get_local_transform_at_distance`, visual
generation) but replaces circular math with a stadium sampler:

- Exports `straight_length_m` and `curve_radius_m`; `length` is computed.
- The UP and DOWN scene nodes use the same straight length and different radii.
- A new `map_to_parallel(distance_m)` returns the distance on the other track
  for the same physical radial location:
  - straights: identical local distance;
  - curves: same angle, other radius;
  - piecewise at the four segment boundaries.
- Proportional scaling must not be used on a stadium; it only works on circles.
- `SceneryDirector._pose_pair`, crossover placement, platform placement, huts,
  wires, and cameras use `map_to_parallel`.

The existing `LTSTrack` sleepers/rails generation continues to iterate distance
and use the transform API, so the visible rails follow the stadium.

### 5.3 Station, blocks and crossovers

Five equal blocks per line:

- UP block length: `250.7964 m`; DOWN block length: `245.7699 m`.
- Station and platform are on the south straight.
- Crossover A at physical `120 m`; Crossover B at physical `240 m`;
  platform between them, so the single-line section is 120 m.
- Station blocks are `UP-B0` and `DOWN-B4`. The indices differ because DOWN
  block numbering follows T3's travel direction (anticlockwise), while physical
  chainage still increases clockwise for both tracks.
- Zone layout: `['zone1', 'zone2', 'zone2', 'zone2', 'zone1']`, so both station
  blocks (`UP-B0`, `DOWN-B4`) are in `zone1`.
- Crossover definitions carry physical and operational positions:

| ID | From | From op offset | To | To op offset | At (physical) |
|---|---|---|---|---|---|
| `X-A` | `UP-B0` | 120.0000 | `DOWN-B4` | 125.7699 | 120.0 |
| `X-B` | `DOWN-B4` | 5.7699 | `UP-B0` | 240.0000 | 240.0 |

The same two physical crossovers serve both operators:

- T1: UP→DOWN at A via `X-A`, DOWN→UP at B via `X-B`.
- T3: DOWN→UP at B via `X-B`, UP→DOWN at A via `X-A`.

`validateConfig` checks that offsets are inside their block, that `atM`
matches the line mapping, and that the crossovers connect existing blocks.

### 5.4 Chainage model

- **Physical distance** increases clockwise on both tracks. Godot always poses
  trains with physical distance.
- **Operational distance** is the backend's block-relative measure and
  increases in each line's traffic direction:
  - UP: `physical = operational`.
  - DOWN: `physical = L_down - operational` (mirrored).
- `travelSign` is constant per train: T1 `+1`, T3 `-1`.
  - Normal DOWN: operational increases, physical decreases, travelSign −1.
  - T1 wrong-line on DOWN: operational decreases, physical increases,
    travelSign +1.
  - T3 wrong-line on UP: operational decreases, physical decreases,
    travelSign −1.
- Godot uses `travelSign` for signed movement, carriage trailing, orientation,
  wheels, and the forward camera. It does not derive direction from the current
  line, because wrong-line trains keep their original physical direction.
- Backend publishes `travelSign` in each train state.

### 5.5 Wildlife compatibility

- Trackside huts remain at physical block boundaries; for DOWN, the reported
  `distanceM` is converted to operational distance before publishing:
  `operational = L_down - physical`.
- Sensor observations publish the animal's along-track chainage (converted for
  DOWN), not the straight-line range, so the backend maps the hazard to the
  correct block.
- The onboard geometric detector uses the train's current `line`, the real
  `trainId`, and reads speed from its owning `LTSTrain`. It publishes a sensor
  observation and can only create suspicion; it cannot confirm a hazard.
- The detector's forward camera rotates with `travelSign`, so it looks in the
  direction of travel on both lines.

## 6. Interlocked Wrong-Line Route

### 6.1 Configuration

Add `wrongLine` to backend config:

- `enabled: true`
- `speedKmh: 30`
- `approachMinM: 40`, `approachMaxM: 220`
- `crossingLengthM: 20` (visual/state crossing zone)
- `holdBeforeEntryM: 80`
- `stopMarginM: 25`
- `timeoutSec: 120`

The section reservation covers `UP-B0` and `DOWN-B4` until the whole train,
including its 60 m length, has cleared the exit.

### 6.2 Eligibility

Computed every tick and published in state for both trains:

- Train is the requester and is between `approachMinM` and `approachMaxM` before
  its entry crossover, travelling toward it.
- The section is clear of all other trains on both lines.
- The opposing train can stop before its protected hold point:
  `v² / (2 · brakeMps2) + stopMarginM` must fit before the section.
- No active hazard in `UP-B0` or `DOWN-B4`, in either `SUSPECTED` or
  `CONFIRMED` stage.
- Neither station block is in a restrictive zone.
- No meet hold and no other route is active.
- Reasons are explicit: `approach`, `section_occupied`, `opposing_too_close`,
  `hazard`, `restrictive_zone`, `meet_active`, `route_busy`, `wrong_phase`.

### 6.3 Lifecycle

| Phase | Behaviour |
|---|---|
| `APPROACH` | Requester continues to the entry at the route speed cap; opposing train receives a 0 km/h hold at the configured point before its entry. |
| `CROSS_ENTRY` | Entry line change; crossing progress 0→1 over 20 m; both blocks reserved. |
| `WRONG_LINE` | Requester moves against the destination line's normal operational direction from entry to exit. Normal `stepTrains` skips this train. |
| `CROSS_EXIT` | Exit line change; progress 0→1 over 20 m; the train continues at route speed. |
| `CLEARANCE` | Section stays reserved until the rear clears the exit by `trainLengthM`. |
| `DONE` | Release hold and reservation; restore normal target speed and normal simulation. |

Cancellation is allowed only during `APPROACH`. After entering `CROSS_ENTRY`,
the move must complete or stop safely. A 120 s timeout triggers a safe stop and
an abort.

### 6.4 Safety

- Hazard appears in the section: stop the route train, phase
  `ABORTED_BLOCKED`; keep the reservation until the hazard clears.
- Opposing train enters the section: emergency stop both trains and publish a
  fault event.
- Cancellation, completion, timeout, and aborts are audited.
- `route:set` permission is required; viewers are read-only.
- Meets are hold-only in the new layout. The random 2G crossover is retired
  (`crossoverChance` defaults to 0, field retained for compatibility) because
  operator wrong-line runs are now the only physical crossovers.

### 6.5 State and API

Snapshot additions:

- `routes.wrongLine.active`: `{trainId, routeId, phase, entryCrossover,
  exitCrossover, progress, heldTrainId, startedAt}` or null.
- `routes.wrongLine.eligibility`: per-train `{eligible, reason,
  distanceToEntryM}`.
- `trains[].travelSign` and `trains[].routePhase`.

Endpoints (following existing JWT/RBAC/audit conventions):

- `GET /api/routes/wrong-line` — active route and eligibility.
- `POST /api/routes/wrong-line {trainId}` — request.
- `POST /api/routes/wrong-line/cancel {trainId}` — cancel during approach.

## 7. Sensor-Slow, Camera-Confirm, Stop

### 7.1 Hazard stages

Wildlife hazards gain a stage:

- `NONE` — no evidence.
- `SUSPECTED` — at least one sensor source is active, but no camera
  confirmation. The train slows.
- `CONFIRMED` — the camera and ML service have confirmed an animal. The train
  stops.

State fields:

- `stage`: `NONE` | `SUSPECTED` | `CONFIRMED`
- `confirmed`: boolean, latched after the first confirmation
- `confidence`: latest ML confidence
- `confirmedAt`, `confirmedBy` (`T1`/`T3` camera), `model`
- `evidence.trackside`, `evidence.onboardSensor`, `evidence.camera`
- `sensorSources`: active sensor names
- `camera`: `{trainId, species, confidence, bbox, at, frameId}` or null

`confirmed` remains latched until the zone reset, even after the animal leaves,
so the stop cannot be released by a single missing frame. Clearing evidence
moves the zone to `RECOVERY_REQUIRED`, which is already restrictive.

### 7.2 Sensor stage

- Trackside huts publish `source: "trackside"` observations.
- The onboard geometric detector publishes `source: "onboard-sensor"` and is
  treated as a sensor, not a camera. It cannot set `CONFIRMED`.
- Sensor detection sets the hazard to `SUSPECTED`, the block aspect to YELLOW,
  and the governed train target to `cautionSpeedKmh` (30 km/h) using service
  braking.
- The block and approach aspects show caution so the train slows before the
  animal.
- The existing trackside ESP32 path is unchanged: the ESP32 reports the sensor
  event and receives the backend alert; no new firmware is required.

### 7.3 Camera confirmation pipeline

**Godot capture:**

- Each train gets a `CameraConfirmation` node with a dedicated `SubViewport`
  (640×360), forward-facing camera at the same front pose as the detector, and
  `world_3d` set to the main world.
- Capture starts only when state contains a `SUSPECTED` hazard on the train's
  line within `cameraConfirmRangeM` (200 m) of the train.
- Capture rate: 2 fps; JPEG quality 70; one in-flight upload at a time; drop
  frames while a request is pending.
- The frame is POSTed as raw `image/jpeg` to
  `POST /api/wildlife/camera/frame` with headers:
  `X-Camera-Token`, `X-Train-Id`, `X-Line`, `X-Block`, `X-Event-Id`,
  `X-Captured-At`.
- Capture stops when the hazard is no longer `SUSPECTED`/`CONFIRMED`, when the
  train is stopped after confirmation, or when the feature is disabled.
- The capture node records the latest result for the HUD and logs upload
  failures without blocking train control.

**Backend:**

- Validate the ingest token, train, line/block, active hazard event, Content-Type,
  body size (1 MB max), and rate (5 fps max per train).
- Forward the raw JPEG to the ML service with a 2 s timeout.
- Apply confirmation using this policy:
  - two consecutive detections at confidence ≥ `0.5` within a 2 s window, or
  - one detection at confidence ≥ `0.75`.
- On confirmation: set `stage = CONFIRMED`, `confirmed = true`, update
  confidence/species/bbox, set the block aspect RED, command the train target to
  0, emit `WILDLIFE_CONFIRMED`, store the confirming frame under
  `backend/data/camera-evidence/<eventId>.jpg` (gitignored, capped), and audit.
- Repeated frames after confirmation only refresh confidence/metadata.
- If the ML service is unavailable or returns 5xx, respond `degraded`, keep the
  hazard `SUSPECTED`, and log once per hazard. Never auto-confirm without a
  model result.
- If the hazard is no longer active, respond `stale` and do not reactivate it.

**ML service (`ml/`):**

- FastAPI app with `POST /detect` (raw image) and `GET /health`.
- Model: `torchvision.models.detection.ssdlite320_mobilenet_v3_large` with the
  COCO pretrained weights, CPU by default. Torchvision, PyTorch, FastAPI, and
  Pillow are already available in the environment.
- Accepted animal classes: bird, cat, dog, horse, sheep, cow, elephant, bear,
  zebra, giraffe. Any accepted class counts as wildlife; the response includes
  the COCO label, confidence, and box.
- Weights are downloaded on first start and cached under `ml/.cache/`; no model
  file is committed. If weights cannot be loaded, `/health` reports
  `modelLoaded: false` and `/detect` returns 503.
- `ML_STUB=1` returns a deterministic high-confidence animal detection for
  backend/Godot tests without downloading weights.
- Configuration: `ML_PORT` (8001), `ML_DEVICE` (cpu), `ML_MIN_CONFIDENCE`
  (0.5), `ML_WEIGHTS_DIR`, `ML_STUB`, `ML_TIMEOUT_SEC`.
- Request logging includes model, latency, detections, and confidence; images
  are not retained by the ML service.

### 7.4 Speed and aspect behavior

- `deriveBlockAspects` treats `SUSPECTED` as YELLOW/caution and `CONFIRMED` as
  RED/stop, unless a stricter aspect already applies.
- `stepTrains` uses:
  - `SUSPECTED`: target speed capped at 30 km/h with service braking.
  - `CONFIRMED`: target speed 0; the train stops in the block/approach.
  - Zone `RECOVERY_REQUIRED` remains restrictive until reset.
- The existing `POST /api/control RESET zone1` clears the latched confirmation
  and the hazard, returning the zone to NORMAL.
- Wrong-line route eligibility rejects both stages.

### 7.5 Safety and failure modes

- ML unavailable: caution persists; no automatic stop; HUD/web show degraded
  camera status.
- False negative: caution remains until sensors clear; the train does not
  resume line speed while suspicion is active.
- False positive: the train stops; the operator inspects and resets.
- Camera/upload failure: retry on the next frame; control never depends on the
  HTTP request completing.
- Low frame rate: caution speed provides stopping margin; the stop decision may
  be later but remains ahead of the animal at the configured ranges.
- Confirmation is backend-authoritative; MQTT observations cannot self-declare
  `CONFIRMED`.
- The ingest token is a shared machine secret (`CAMERA_INGEST_TOKEN`), compared
  in constant time; frames are capped and not exposed on the state API.

### 7.6 APIs and state

- `POST /api/wildlife/camera/frame` — raw JPEG plus headers; machine token;
  returns `{ok, confirmed, degraded, stage, confidence, species}`.
- `GET /api/wildlife/camera/health` — backend view of the ML service.
- State `wildlife.hazards[]` includes `stage`, `confirmed`, `confidence`,
  `sensorSources`, `camera`, and evidence.
- Config adds `cameraConfirm` and `ml` blocks:
  - `cameraConfirm`: `{enabled, minConfidence, confirmFrames, confirmWindowSec,
    singleFrameConfidence, cameraRangeM, captureFps, frameWidth, frameHeight,
    jpegQuality, evidenceTtlSec}`
  - `ml`: `{url, timeoutMs}`

## 8. Godot Rendering, Camera, and HUD

- `FleetController` converts operational distance to physical distance, sets
  `travelSign`, and applies state-driven crossings.
- `LTSTrain` gains `travel_sign`; it uses it for movement, carriage offsets,
  orientation, wheel rotation, and the camera. `set_track_blend` remains, but a
  route crossing sets its progress from backend state each snapshot.
- Timed blending is retained only for non-route/manual test transitions.
- Crossover blades activate at the physical node A or B named by the route.
- The camera confirmation node is a child of each train; it uses a SubViewport
  so the captured frame is the train's forward view, not the operator camera.
- HUD adds:
  - route line, e.g. `WRONG-LINE T1  UP→DOWN→UP  42%  T3 HOLD DOWN-B3`;
  - wildlife stage line, e.g. `WILDLIFE T1  SUSPECTED  29 km/h  camera: waiting`
    or `CONFIRMED  elephant 0.87  STOP`;
  - direction indicators and camera degraded state.
- Camera presets and captures are updated for the stadium and the south-straight
  station.

## 9. Web Dashboard

- A "Wrong-line run" card for the selected train:
  - eligibility badge and reason;
  - start button;
  - phase, progress, held train, and cancel (approach only).
- Wildlife evidence:
  - stage (`SUSPECTED`/`CONFIRMED`), confidence, species, source, and confirming
    train;
  - camera/ML degraded state.
- Direction indicators for UP and DOWN.
- Uses the existing state stream and auth; viewers see status only.

## 10. Data Flow

1. Operator clicks start in the web dashboard.
2. `POST /api/routes/wrong-line` validates eligibility under a route lock.
3. Backend reserves blocks, applies the opposing hold, and publishes state.
4. Godot and web render phase, progress, and hold.
5. Backend advances the route train through the phases and publishes line and
   crossing changes.
6. On clearance, holds and reservations are released; normal traffic resumes.
7. Separately, a sensor observation creates `SUSPECTED`, slows the train, and
   starts camera capture.
8. Godot uploads JPEG frames to the backend; the backend calls the ML service.
9. Confirmation upgrades the hazard to `CONFIRMED`, stops the train, and updates
   HUD/web; reset clears it.

## 11. Testing and Acceptance

### 11.1 Backend

- Topology validation: new lengths, block boundaries, station blocks, zone map,
  crossover offsets and physical positions.
- Eligibility matrix: approach window, section occupied, opposing stopping
  distance, hazard stage, restrictive zone, meet active, route busy.
- Lifecycle: approach → entry → wrong line → exit → clearance → done; hold
  applied/released; line and offset state; cancellation and timeout; hazard
  abort; audit and RBAC.
- Meet compatibility: hold-only behaviour, no random teleport crossover.
- Wildlife mapping: DOWN chainage conversion and correct block hazard.
- Staged wildlife: sensor → `SUSPECTED` YELLOW/caution; camera → `CONFIRMED`
  RED/0; latched confirmation; reset; wrong-line rejection for both stages.
- Camera endpoint: token, size/rate limits, stale/unknown event, degraded ML,
  confirmation policy (one high-confidence frame and two consecutive frames),
  idempotency, audit, evidence file cap.

### 11.2 ML service

- Detector unit tests with a stub model: preprocessing, class filtering,
  confidence sorting, box output.
- API tests: `/health`, `/detect` with stub, invalid image, oversized body,
  model-unavailable path.
- Optional real-model smoke test when weights are present; skipped with a clear
  message otherwise.
- No network access required for the default test suite (`ML_STUB=1`).

### 11.3 Godot

- Stadium: poses continuous across all four segment seams; `map_to_parallel`
  matches physical correspondence on straights and curves.
- Opposite running: T3 moves anticlockwise with correct orientation, camera,
  and carriage order; T1 remains clockwise.
- Crossovers: state-driven progress, no freeze/snap; correct blade node.
- Wrong-line states and HUD text.
- T3 detector fixes: line, train ID, speed, local stop, sensor-only source.
- Camera confirmation node: starts only on suspicion, stops when idle, uploads
  JPEG bytes (mock HTTP), handles degraded responses, and leaves control
  unaffected on failure.
- Existing suites updated and passing.

### 11.4 Integration and acceptance

- Live backend + Godot + web run:
  - operator can start only when eligible;
  - T3 visibly stops before B;
  - T1 crosses at A, runs the 120 m wrong-line section, returns at B;
  - section stays reserved until T1's rear clears;
  - T3 resumes without overlap;
  - line, block, offset, and visuals agree; no snap.
- Wildlife chain:
  - trackside/onboard sensor triggers `SUSPECTED` and the train slows;
  - camera frames reach the ML service (stub and, when weights are present,
    real model);
  - confirmation triggers `CONFIRMED`, RED, and a full stop;
  - reset returns the zone to NORMAL.
- Capture a GIF and before/mid/after stills under `/tmp/opencode`, including a
  camera frame with the detection box.
- Update `docs/porting/acceptance.md` with the stadium, route, and wildlife
  evidence.
- Full gate: Godot test suite, backend tests, ML service tests, ESP32 native
  15/15, firmware build, web build.

## 12. Risks and Mitigations

- **Stadium chainage/mapping is the highest risk.** Add focused tests for seam
  continuity, parallel mapping, and physical/operational round trips.
- **Backend–Godot length drift.** Add a consistency test that compares the
  configured line lengths/block lengths with the scene's `TrackRegistry`
  values (via a generated fixture or a test that loads both sides).
- **Meet timing changes** from the longer loop. Re-tune meet gaps and
  station-window offsets; keep meets hold-only.
- **Scene framing** changes. Update cameras, terrain, lake, buildings, and
  capture scripts; verify with headless screenshots.
- **Wildlife regressions** from the DOWN chainage mirror. Cover trackside and
  onboard observations on both lines in tests.
- **Route conflicts** with meets, ESP32 holds, and manual speed controls.
  Reject overlapping commands and cover the matrix in tests.
- **Deer is not a COCO class.** The camera accepts any COCO animal class and
  the acceptance test uses the elephant asset; the deer path is best-effort. A
  future fine-tuned model can improve deer detection without changing the
  pipeline.
- **ML latency/CPU load.** CPU inference at 2 fps with a 640×360 frame; caution
  speed provides margin. Health/degraded telemetry is always visible.
- **Camera capture cost.** Capture only while suspicion is active; one
  in-flight upload; 640×360 JPEG quality 70.
- **False positives/negatives.** Backend-authoritative confirmation, latched
  stop, operator reset; no safety decision depends on a single frame.
- **Headless tests.** Stub ML and a camera-capture test mode avoid GPU/model
  dependencies; real-model smoke is optional.

## 13. Implementation Milestones

### Phase 1 — Stadium and opposite running

1. Stadium sampler and `map_to_parallel` with TDD.
2. Scene track nodes, station, crossovers, scenery, cameras, captures.
3. Backend config lengths, blocks, zones, station, crossovers, validation.
4. Direction-aware Godot movement/orientation/camera.
5. Wildlife chainage and T3 detector fixes.
6. Full suites and visual captures.

### Phase 2 — Interlocked wrong-line route

1. Route eligibility and state machine with TDD.
2. Holds, reservations, clearance, safety, audit, API.
3. State-driven crossover animation, HUD.
4. Web operator card and direction indicators.
5. Integration tests, live capture, acceptance update.
6. Full gate.

### Phase 3 — Sensor-slow, camera-confirm, stop

1. FastAPI ML service with torchvision SSDLite320, stub mode, health, tests.
2. Backend staged hazard model, aspects, camera endpoint, ML client, audit.
3. Godot camera capture/upload node, HUD, web evidence.
4. Integration with animal spawn: sensor suspicion → caution → camera frames →
   confirmation → stop → reset.
5. Real-model smoke test (when weights available), capture evidence, acceptance
   update.
6. Full gate.

## 14. Verification Commands

- Godot: `bash godot/tests/run_tests.sh`
- Backend: isolated broker on 1884, then `npm --prefix backend test`
- ML: `cd ml && python -m pytest`; run service with
  `ML_STUB=1 uvicorn app:app --port 8001`
- ESP32: `pio test -e native --project-dir esp32`;
  `pio run -e esp32dev --project-dir esp32`
- Web: `npm --prefix web run build`
- Captures: `xvfb-run -a <godot> --path godot --resolution 1440x900
  --rendering-method gl_compatibility --script res://tests/capture_<name>.gd`

## 15. Decisions Locked In

- Stadium loop: 250 m straights, 120 m/116 m curves, 4 m spacing.
- Station and A/B on the south straight; A/B 120 m apart.
- T1 clockwise, T3 anticlockwise, continuous running.
- Wrong-line move is operator-triggered, A→B→A, with approach-window
  eligibility.
- Automatic hold of the opposing train; interlocked reservations; audit.
- Operator UI in both web dashboard and Godot HUD.
- Meets become hold-only; random crossovers retired.
- Wildlife is two-stage: sensor → `SUSPECTED` and slow; camera/ML →
  `CONFIRMED` and stop.
- Camera is each train's forward view; ML is FastAPI + torchvision SSDLite320
  MobileNetV3, CPU, COCO animal classes, stub mode for tests.
- Confirmation policy: two consecutive frames ≥0.5 within 2 s, or one frame
  ≥0.75; backend-authoritative; latched stop until reset.
- No ESP32-CAM hardware, custom training, or cloud streaming in this scope.
