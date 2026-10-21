# Stage C2 / Slice 2A — Backend Live Fleet and Interlocking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use `- [ ]` checkboxes. Every task is TDD: failing test, verify RED, implement, verify GREEN, commit.

**Goal:** Make the backend the authoritative source of truth for a two-train, double-track fleet with block occupancy, per-block aspects, crossover route interlocking, per-block MQTT signals, and secured REST control. The existing Godot scene must still run unchanged.

**Architecture:** `config.js` describes per-line block lengths, two trains (`T1` UP, `T3` DOWN), and one station crossover pair. `railway.js` builds the topology including crossovers. `routes.js` owns the mutually exclusive crossover interlock. `state.js` owns `trains[]`, `blocks[]`, `lines[]`, `station`, and `routes`; `tick(dtSec)` advances the fixed-step simulation. `loop.js` drives ticks at `simulation.tickMs` only while the broker is connected. `bus.js` publishes retained `railway/state` and `railway/signal/{blockId}`. The unauthenticated `POST /api/event` route is removed; `POST /api/route` and per-train `POST /api/speed` are added.

**Tech stack:** Node.js ESM, Express, mqtt, `node:test` + `assert/strict`, `better-sqlite3`. No new dependencies.

**Spec:** [`../specs/2026-10-21-stage-c2-double-track-multitrain-design.md`](../specs/2026-10-21-stage-c2-double-track-multitrain-design.md). Prior related plan: [`2026-10-19-stage-a2-block-signalling.md`](./2026-10-19-stage-a2-block-signalling.md).

## Global Constraints

- ESM only; tests run with `MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test` against a disposable broker.
- Do not add npm dependencies.
- Zones are exactly `['zone1', 'zone2']`; speeds clamp to `0..80` km/h.
- Physics is illustrative: brake `2.0 m/s²`, accel `0.6 m/s²`, caution `30 km/h`.
- Deterministic: fixed tick, no wall-clock in physics; snapshots publish at ≤ 2 Hz.
- Least-privilege ACLs; never `railway/#`. Godot gets read-only `railway/state` and `railway/signal/+`, keeps wildlife writes, loses `zoneN/train` writes.
- Legacy `snapshot().train` is retained as a deprecated summary of `trains[0]`.
- Zone-only unit configs keep working: if `config.topology` is absent, `makeState` runs in legacy zone-only mode with no fleet.
- Commit after each validated task using `feat:`/`fix:`/`test:` style.

## File Structure

- Modify `backend/src/config.js` — per-line lengths, two trains, crossovers, validation.
- Modify `backend/src/railway.js` — per-line block lengths, crossovers.
- Create `backend/src/routes.js` — crossover route interlock.
- Modify `backend/src/simulation.js` — block-boundary stop enforcement.
- Modify `backend/src/state.js` — optional fleet, routes, tick, snapshot.
- Create `backend/src/loop.js` — fixed-timestep loop.
- Modify `backend/server.js` — loop lifecycle, subscription list.
- Modify `backend/src/bus.js` — retained per-block signals.
- Modify `backend/src/validate.js` — `validateRoute`, per-train `validateSpeed`.
- Modify `backend/src/control.js` (route) and `backend/src/routes/control.js` — route endpoint, per-train speed.
- Modify `backend/src/rbac.js` — `route:set`.
- Modify `backend/src/app.js` — remove `simulationRouter`.
- Delete `backend/src/routes/simulation.js`.
- Modify `mosquitto/acl_file` — block signal + godot state reads; retire zone train writes.
- Tests: `railway.test.js`, `routes.test.js`, `simulation.test.js`, `state.test.js`, `loop.test.js`, `bus.test.js`, `config.test.js`, `control_routes.test.js`, `broker_acl.test.js`, `read_routes.test.js`, `e2e.test.js`.

---

### Task 1: Config and topology — per-line lengths, two trains, crossovers

**Files:** `backend/src/config.js`, `backend/src/railway.js`, `backend/test/config.test.js`, `backend/test/railway.test.js`

**Interfaces:** `buildTopology(config) -> { blocks, lines, station, crossovers }`; each block gains `lengthM` from `lineLengthM[line] / blocksPerLine` rounded to 3 dp; `blockById`, `nextBlockId` unchanged.

- [x] Step 1: Failing tests. In `config.test.js`: `config.trains.map(t=>t.id)` deep-equals `['T1','T3']`; `config.topology.lineLengthM.UP` is `753.9822`; `DOWN` is `728.8495`; `config.topology.crossovers` deep-equals `[{id:'X-UP-DOWN',from:'UP-B2',to:'DOWN-B2'},{id:'X-DOWN-UP',from:'DOWN-B2',to:'UP-B2'}]`. In `railway.test.js`: UP blocks each `150.796` m, DOWN blocks each `145.77` m; `topo.crossovers` round-trips both definitions.
- [x] Step 2: Run `node --test test/config.test.js test/railway.test.js`; expect FAIL.
- [x] Step 3: Implement config values and topology derivation. `buildTopology` uses `t.lineLengthM?.[line] ?? t.blockLengthM * t.blocksPerLine` and `Math.round((lineLength / t.blocksPerLine) * 1000) / 1000`. Copy `t.crossovers ?? []` into `topology.crossovers`. `validateConfig` checks each line length > 0, `lineLengthM` keys match `lines`, and crossover endpoints exist in `blocks`.
- [x] Step 4: Run tests; expect PASS.
- [x] Step 5: Commit `feat(backend): two-train double-track topology config`.

### Task 2: Crossover route interlock

**Files:** Create `backend/src/routes.js`, `backend/test/routes.test.js`

**Interfaces:** `makeRoutes({ topology, zones, trains }) -> { list(), requestRoute({trainId, routeId}), tick(), activeRoute() }`.
- `requestRoute` rejects unknown route, unknown train, train not on `from` block, destination occupied by another train, restrictive zone at either endpoint, and any second active route.
- On success, atomically sets `train.line`/`train.block` to the destination block, `train.offsetM = 0`, marks the route active with `{routeId, trainId, from, to, grantedAtTick}`.
- `tick()` releases the route when the train front has left the destination block.

- [x] Step 1: Failing tests in `routes.test.js`: grant `T1` `UP-B2 -> DOWN-B2`, reject a second route while active, reject `T3` `DOWN-B2 -> UP-B2` when `UP-B2` is occupied, reject when `zone1` has `wildlifeDetected`, release after the train leaves `DOWN-B2`, then allow the opposite route.
- [x] Step 2: Run `node --test test/routes.test.js`; expect FAIL (module missing).
- [x] Step 3: Implement `routes.js` using `blockById` and `isZoneRestrictive`.
- [x] Step 4: Run tests; expect PASS.
- [x] Step 5: Commit `feat(backend): crossover route interlock`.

### Task 3: Simulation stop-at-red enforcement

**Files:** `backend/src/simulation.js`, `backend/test/simulation.test.js`

**Interfaces:** `stepTrains` must never advance a train front into a block whose aspect is `RED`.

- [x] Step 1: Failing test: train at `UP-B0` offset `290`, speed `80`, `aspects['UP-B1']='RED'`; after `stepTrains(..., dtSec: 1)`, `t.block === 'UP-B0'` and `t.offsetM === 300` and `t.speedKmh === 0`.
- [x] Step 2: Run `node --test test/simulation.test.js`; expect FAIL.
- [x] Step 3: Implement: inside the advance loop, when the requested advance reaches the block boundary and the next block aspect is `RED`, clamp `t.offsetM` to `cur.lengthM`, zero speed, and stop advancing.
- [x] Step 4: Run tests; expect PASS.
- [x] Step 5: Commit `fix(backend): hold trains at red block boundaries`.

### Task 4: State fleet integration and routes

**Files:** `backend/src/state.js`, `backend/test/state.test.js`

**Interfaces:** `makeState({config, topology})` returns `{snapshot, applyCommand, applySpeed, setWildlife, setSensor, tick, setBrokerConnected, requestRoute}`. `snapshot()` includes `zones[z].signal` (zone layer), `zones[z].blocks`, `train` (deprecated `trains[0]` summary), `trains`, `lines`, `blocks` (each with `signal` and `occupiedBy`), `station`, `routes`, `overall`, `comm`, `updatedAt`. `tick(dtSec)` runs `routes.tick()` then aspects then `stepTrains` then `occupyBlocks`.

- [x] Step 1: Failing tests: fleet snapshot exposes 2 trains, 10 blocks, per-block aspects and `routes`; `T1` starts `UP-B0`; tick advances `T1`; `requestRoute('T1','X-UP-DOWN')` at `UP-B2` succeeds and rejects a second route; legacy zone-only `makeState({config:{zones}})` still returns the old shape.
- [x] Step 2: Run `node --test test/state.test.js`; expect FAIL.
- [x] Step 3: Implement, keeping the existing zone-only behavior when `config.topology` is absent. Preserve the current wildlife/sensor semantics (`setWildlife` clear leaves `RECOVERY_REQUIRED`).
- [x] Step 4: Run tests; expect PASS.
- [x] Step 5: Commit `feat(backend): authoritative fleet state with route interlock`.

### Task 5: Fixed-timestep loop and server wiring

**Files:** Create `backend/src/loop.js`, `backend/test/loop.test.js`, modify `backend/server.js`

**Interfaces:** `makeLoop({ state, bus, config, intervalMs }) -> { start(), stop(), step(), isRunning() }`. `step()` calls `state.tick(intervalMs/1000)` then `bus.snapshot()`. `start()` is idempotent and `unref()`s the timer.

- [x] Step 1: Failing test: with a fake mqtt and fleet config, call `loop.step()` twice, assert `railway/state` published twice and `T1.offsetM` advanced.
- [x] Step 2: Run `node --test test/loop.test.js`; expect FAIL.
- [x] Step 3: Implement `loop.js`; wire `server.js` to `start()` on MQTT `connect`, `stop()` on `close`, and drop `railway/zoneN/train` from the subscription list.
- [x] Step 4: Run tests; expect PASS.
- [x] Step 5: Commit `feat(backend): run simulation loop while broker is connected`.

### Task 6: Per-block MQTT signals and ACL

**Files:** `backend/src/bus.js`, `backend/test/bus.test.js`, `mosquitto/acl_file`, `backend/test/broker_acl.test.js`

**Interfaces:** `bus.snapshot()` also publishes retained `railway/signal/{blockId}` with `{block, line, zone, signal, occupiedBy, timestamp}`.

- [x] Step 1: Failing tests: bus publishes retained `railway/signal/UP-B0`; broker ACL grants `godot` read of `railway/state` and `railway/signal/UP-B0`, denies `godot` publish to `railway/zone1/train`, and denies `esp32` read of `railway/signal/UP-B0`.
- [x] Step 2: Run tests; expect FAIL.
- [x] Step 3: Implement bus publication and ACL entries: godot `read railway/state`, `read railway/signal/+`; dashboard `read railway/signal/+`; backend `write railway/signal/+`; remove godot `write railway/zoneN/train`; remove backend `read railway/zoneN/train` and `write railway/zoneN/train` is already absent.
- [x] Step 4: Restart the disposable broker, run tests; expect PASS.
- [x] Step 5: Commit `feat(backend): publish per-block signals with least-privilege ACL`.

### Task 7: REST — remove `/api/event`, add `/api/route`, per-train speed

**Files:** `backend/src/validate.js`, `backend/src/rbac.js`, `backend/src/routes/control.js`, `backend/src/app.js`, delete `backend/src/routes/simulation.js`, tests `validate.test.js`, `rbac.test.js`, `control_routes.test.js`, `e2e.test.js`, `read_routes.test.js`.

**Interfaces:**
- `validateRoute(body, {trains}) -> {ok, value:{request_id, trainId, routeId}}`; unknown train or route is `400`; duplicate `request_id` is `400`; route conflict/hazard is `409`.
- `validateSpeed(body, {zones, trainIds})` accepts `{trainId, speedKmh}` or `{zone, speedKmh}`; unknown `trainId` is `400`.
- `POST /api/event` returns `404`. `POST /api/route` requires `route:set` (operator, admin). RBAC: viewer unchanged, operator `+route:set`, admin `+route:set`.

- [x] Step 1: Failing tests: `/api/event` 404; anonymous `/api/route` 401; viewer 403; operator grants route 200 and repeats 409/400; unknown train speed 400; `T1` speed 200 changes `trains[0].targetSpeedKmh`.
- [x] Step 2: Run tests; expect FAIL.
- [x] Step 3: Implement validation, RBAC, route endpoint, speed extension, delete simulation router, drop it from `app.js`.
- [x] Step 4: Run tests; expect PASS.
- [x] Step 5: Commit `feat(backend)!: secure route API and retire /api/event`.

### Task 8: Full regression, docs, and slice commit

- [x] Step 1: Start disposable broker on `127.0.0.1:1884`; run `MQTT_URL=mqtt://127.0.0.1:1884 npm --prefix backend test`; expect all tests PASS.
- [x] Step 2: Run `bash godot/tests/run_tests.sh`; expect 16/16 PASS (unchanged scene compatibility).
- [x] Step 3: Run `cd esp32 && pio test -e native` and `pio run -e esp32dev`; expect PASS.
- [x] Step 4: Update `docs/porting/acceptance.md` and `README.md` with the Stage 2A evidence and the removed endpoint note.
- [x] Step 5: Commit `docs(c2): record stage 2A backend-live evidence`.
- [x] Step 6: Live acceptance: run the server against the disposable broker and verify the 2 Hz state stream with two moving trains, retained per-block signals, and a successful `X-UP-DOWN` grant after holding `T3`; the destination-occupied attempt returned 409.
- [x] Step 7: Fix found regression: a train stopped at 119.5 m because its own 60 m consist occupied the next block (`RED`); exclude own-occupancy from the aspect hold, test in `simulation.test.js`, commit `fix(backend): exclude own consist from red-aspect hold`; rerun all suites (84/84).

## Stage 2A Exit Gate

- `snapshot()` contains two trains in one authoritative state, ten blocks, per-block aspects, station, and route state.
- No train can enter a red block or an occupied crossover destination; crossover routes are mutually exclusive and release after clear.
- Dashboard/legacy clients still read `zones`, `train`, `comm`; Godot reads `railway/state` and `railway/signal/+` without publish rights.
- `/api/event` is gone; `/api/speed` and `/api/route` are authenticated, validated, and audited.
- Full backend, Godot, and ESP32 suites pass.

Do not start 2B until every exit-gate item has executed evidence.

**Exit gate met (2026-10-21):** backend 84/84, Godot 16/16, ESP32 native 14/14, `pio run -e esp32dev` PASS, `web` build PASS, live broker check and crossover grant recorded in `docs/porting/acceptance.md`. 2B may start.
