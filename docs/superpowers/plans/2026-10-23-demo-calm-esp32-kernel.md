# Demo-Calm Train Ops + ESP32 Communicator Kernel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop trains stalling in demos (auto-wildlife off by default, robust speed restore) and surface the Wokwi ESP32 as the web UI's communicator kernel with telemetry-freshness liveness and verified command acks.

**Architecture:** Backend-only additions plus one Godot config change and one Web panel. Speed restore is a small pure util used by `meets.js` and `wrong_line.js`, routed through an optional `logEvent` hook that `state.js` wires to the events store. ESP32 liveness is tracked in `state.js` from telemetry-receipt timestamps; acks live in a new `command_tracker.js` module fed by `routes/control.js` (issued) and `ingest.js` (acknowledged on later ESP32 telemetry). The web reads the new `esp32` + `esp32Commands` fields from the existing `/api/state` poll — no new connections.

**Tech Stack:** Node/Express (ESM, node:test), React/TypeScript/Vite, Godot config, existing npm test scripts.

**Spec:** `docs/superpowers/specs/2026-10-23-demo-calm-esp32-kernel-design.md`

## Global Constraints

- Liveness is telemetry freshness: `online` only when `now - lastTelemetryAt <= config.esp32TelemetryTimeoutSec * 1000`. Broker `comm.mqttConnected` never contributes.
- An MQTT publish never marks a command acknowledged; only ESP32 telemetry ingested after the command was issued counts (device response), within `config.commandAckTimeoutSec`.
- Speed restore fallback value is `48` (matching `config.simulation.defaultTargetSpeedKmh`); a saved speed is used only when finite and `> 0` — `null`, `0`, negative, and non-finite all fall back.
- Every fallback restore emits event `{ type: 'SPEED_RESTORED_FALLBACK', trainId, reason, restoredKmh, attemptedSavedKmh, timestamp }` (fallback only — a natural saved-value restore logs nothing).
- Two-frame camera confirmation and confirmed-hazard semantics are untouched; all existing backend tests must stay green.
- Backend port 3001; run tests with `npm --prefix backend test`, web build with `npm --prefix web run build`.

## Review Focus

- Broker connected but ESP32 silent minutes → panel must read **offline**, not online. Pinned: state liveness tests (Task 4).
- Command published, ESP32 returns no telemetry → command must progress PENDING → TIMED_OUT, never ACKNOWLEDGED. Pinned: command_tracker tests (Task 5).
- Meet saves a hold over a train the operator stopped at 0 → release falls back to 48 so the demo keeps moving. Pinned: meets test (Task 2).
- ESP32 panel before any telemetry ever arrives → UI shows "no telemetry yet" and offline, never crashes on undefined fields. Pinned: App.tsx guards + web build (Task 7).
- Telemetry ingested well before a command is issued must not ack that future command. Pinned: command_tracker ordering test (Task 5).

---

### Task 1: `speed_restore` util module

**Files:**
- Create: `backend/src/speed_restore.js`
- Test: `backend/test/speed_restore.test.js`

**Interfaces:**
- Produces: `restoreSpeed(train, savedKmh, { reason, fallbackKmh, onRestore }) -> restoredKmh:number`. Mutates `train.commandedSpeedKmh`. Validity rule: finite and `> 0` uses `savedKmh`; otherwise uses `fallbackKmh`. When falling back (and `onRestore` is a function), calls `onRestore({ type: 'SPEED_RESTORED_FALLBACK', trainId: train.id, reason, restoredKmh, attemptedSavedKmh: savedKmh ?? null, timestamp: new Date().toISOString() })`. Natural restores emit nothing.

- [ ] **Step 1: Write the failing test**

```js
import test from 'node:test';
import assert from 'node:assert';
import { restoreSpeed } from '../src/speed_restore.js';

test('restores saved speed when finite and positive', () => {
  const t = { id: 'T1', commandedSpeedKmh: null };
  let log = null;
  const r = restoreSpeed(t, 30, { reason: 'MEET_HOLD_RELEASE', fallbackKmh: 48, onRestore: (e) => (log = e) });
  assert.strictEqual(r, 30);
  assert.strictEqual(t.commandedSpeedKmh, 30);
  assert.strictEqual(log, null); // no fallback event for a valid restore
});

for (const [label, saved] of [['null', null], ['zero', 0], ['negative', -5], ['non-finite', NaN]]) {
  test(`falls back to 48 with SPEED_RESTORED_FALLBACK when saved is ${label}`, () => {
    const t = { id: 'T3', commandedSpeedKmh: saved };
    const events = [];
    const r = restoreSpeed(t, saved, { reason: 'WRONG_LINE_FINISH', fallbackKmh: 48, onRestore: (e) => events.push(e) });
    assert.strictEqual(r, 48);
    assert.strictEqual(t.commandedSpeedKmh, 48);
    assert.strictEqual(events.length, 1);
    assert.strictEqual(events[0].type, 'SPEED_RESTORED_FALLBACK');
    assert.strictEqual(events[0].trainId, 'T3');
    assert.strictEqual(events[0].reason, 'WRONG_LINE_FINISH');
    assert.strictEqual(events[0].restoredKmh, 48);
    assert.strictEqual(events[0].attemptedSavedKmh, saved === null ? null : saved);
    assert.ok(events[0].timestamp);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm --prefix backend test -- --test-run --test-name-pattern="speed_restore" 2>/dev/null; node --test backend/test/speed_restore.test.js`
(If the repo's test script differs, use `node --test backend/test/speed_restore.test.js`.)
Expected: FAIL — `Cannot find module '../src/speed_restore.js'`

- [ ] **Step 3: Implement `speed_restore.js`**

Export exactly `restoreSpeed(train, savedKmh, { reason = 'UNKNOWN', fallbackKmh = 48, onRestore = null })` per the interface above. One if, one assignment, one callback call.

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test backend/test/speed_restore.test.js`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/speed_restore.js backend/test/speed_restore.test.js
git commit -m "feat: shared speed-restore util with logged 48 km/h fallback"
```

### Task 2: Meet hold release uses speed restore; `logEvent` plumbing

**Files:**
- Modify: `backend/src/meets.js:22` (factory param), `file:81-84` (`releaseHold`)
- Modify: `backend/src/state.js:10-15` (constructor call sites), `makeState` signature at `file:16`
- Modify: `backend/server.js:11` (create `events` before `state`, pass `logEvent`)
- Test: `backend/test/meets.test.js` (append)

**Interfaces:**
- Produces: `makeMeetScheduler({ ...existing, onRestore = null })` — `onRestore(event)` is invoked with the Task 1 event object whenever releaseHold takes the fallback branch.
- Consumes: Task 1 `restoreSpeed`.
- Produces: `makeState({ config, topology, logEvent = null })` analogously passes `(e) => { lastEvent = \`Speed restored to ${e.restoredKmh} km/h for ${e.trainId}\`; logEvent?.(e); }` as `onRestore` to both `makeMeetScheduler` and `makeWrongLine`.
- Produces: `server.js` order: `const events = makeEvents();` moves **above** `const state = makeState({ config, logEvent: (e) => events.record(e) });` — so fallback events land in `/api/events`.

- [ ] **Step 1: Write the failing test (append to `meets.test.js`, follow existing harness there)**

```js
test('releaseHold falls back to 48 and logs when operator never set a speed', () => {
  const restores = [];
  const trains = makeTwoTrains(); // existing helper: T1 UP + T3 DOWN at station; leave commandedSpeedKmh null
  const scheduler = makeMeetScheduler({ ...existingHarness, onRestore: (e) => restores.push(e) });
  forceTriggerMeet(); // existing helper from this file's trigger path
  stepScheduler past HOLDING start so the holder is held;
  assert.strictEqual(holder.commandedSpeedKmh, 0);
  tick scheduler until release; // hold time elapses
  assert.strictEqual(holder.commandedSpeedKmh, 48);
  assert.strictEqual(restores.length, 1);
  assert.strictEqual(restores[0].reason, 'MEET_HOLD_RELEASE');
  assert.strictEqual(restores[0].trainId, holder.id);
});
```

(Write against the file's real helpers/movement API — the trigger and tick paths used by the existing `HELD` outcome test are the model. The assertions above are the contract.)

Also pin the zero case: same flow but holder's commanded speed first set to 0 via the harness's speed path before the hold; release must also restore 48 (`attemptedSavedKmh` 0), not 0.

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test backend/test/meets.test.js`
Expected: FAIL — releaseHold restores to the saved `null` (train becomes `null`/0) and `restores` stays empty.

- [ ] **Step 3: Implement**

`releaseHold()`:

```js
const restored = restoreSpeed(holder, active.savedCommandedSpeed, {
  reason: 'MEET_HOLD_RELEASE', fallbackKmh: 48, onRestore,
});
```

Factory destructure gains `onRestore = null`. Also record `restoredKmh: holder.commandedSpeedKmh` on the HELD history entry when a hold ends in release.

- [ ] **Step 4: Run tests**

Run: `node --test backend/test/meets.test.js && node --test backend/test/state.test.js`
Expected: PASS (existing meets contracts unaffected; state tests still green with default `logEvent = null`)

- [ ] **Step 5: Commit**

```bash
git add backend/src/meets.js backend/src/state.js backend/server.js backend/test/meets.test.js
git commit -m "feat: meet hold release restores safe cruise speed with logged fallback"
```

### Task 3: Wrong-line `finish()` uses speed restore

**Files:**
- Modify: `backend/src/wrong_line.js:7` (factory param `onRestore = null`), `file:113-122` (`finish`)
- Modify: `backend/src/state.js:90` (pass `onRestore`)
- Test: `backend/test/wrong_line.test.js` (append)

**Interfaces:**
- Consumes: Task 1 `restoreSpeed`; Task 2's already-added `onRestore` param on `makeState`.
- Produces: `makeWrongLine({ ...existing, onRestore = null })`; `finish(event)` restores via `restoreSpeed(train, active.savedRouteSpeed, { reason: 'WRONG_LINE_ROUTE_TRAIN', fallbackKmh: 48, onRestore })` and `restoreSpeed(opponent, active.savedOpponentSpeed, { reason: event, fallbackKmh: 48, onRestore })`.

- [ ] **Step 1: Write the failing test**

Drive the existing wrong-line harness (the same path as `WRONG_LINE_COMPLETED` in this test file) with route-train and opponent `commandedSpeedKmh` left `null`, onRestore collector wired:
assert after completion `train.commandedSpeedKmh === 48`, `opponent.commandedSpeedKmh === 48`, exactly two fallback events with reasons `'WRONG_LINE_ROUTE_TRAIN'` and `'WRONG_LINE_COMPLETED'` (the last event's name is the opponent reason), one per train id.

- [ ] **Step 2: Run to verify fails**

Run: `node --test backend/test/wrong_line.test.js`
Expected: FAIL — speeds restored to `null`/no events.

- [ ] **Step 3: Implement `finish()` per the interface above; pass `onRestore` at the `state.js:90` `makeWrongLine` call.**

- [ ] **Step 4: Run tests**

Run: `node --test backend/test/wrong_line.test.js backend/test/meet_pass.test.js`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/wrong_line.js backend/src/state.js backend/test/wrong_line.test.js
git commit -m "feat: wrong-line finish restores safe cruise speed with logged fallback"
```

### Task 4: ESP32 liveness tracking in state + config knobs

**Files:**
- Modify: `backend/src/config.js:117` (`sim` config vicinity — add after `esp32Zone` line 15)
- Modify: `backend/src/state.js` (`newZone`, `makeState` locals, snapshot)
- Test: `backend/test/state.test.js` (append)

**Interfaces:**
- Produces config: `esp32TelemetryTimeoutSec: Number(process.env.ESP32_TELEMETRY_TIMEOUT_SEC || 15)`, `commandAckTimeoutSec: Number(process.env.COMMAND_ACK_TIMEOUT_SEC || 10)` (both in `config`).
- Produces state: `markEsp32Telemetry(zone, atMs = Date.now())` — records `zones[zone].esp32LastTelemetryAtMs`. Snapshot (both fleet and legacy paths) adds top-level `esp32`:
  - zone = `config.esp32Zone || config.zones[0]`
  - `{ zone, online, lastSeenSec, sensorHealthy, nearAnimal }` where `lastSeenSec = Math.floor((Date.now() - atMs) / 1000)` (`null` when never seen), `online = lastSeenSec !== null && lastSeenSec <= config.esp32TelemetryTimeoutSec`, health/near from the zone's existing `sensorHealthy`/`esp32NearAnimal`.
  - Liveness computation never consults `comm.mqttConnected`.

- [ ] **Step 1: Write the failing tests (append to `state.test.js`)**

```js
test('esp32 snapshot: never-seen device is offline with null lastSeenSec', ...)
// no markEsp32Telemetry call; snapshot().esp32 -> { online: false, lastSeenSec: null, sensorHealthy: true, nearAnimal: false, zone: 'zone1' }

test('esp32 snapshot: fresh telemetry is online', ...)
// state.markEsp32Telemetry('zone1'); snapshot().esp32.online === true; lastSeenSec === 0

test('esp32 snapshot: telemetry older than timeout is offline even with mqtt alive', ...)
// mark with atMs = Date.now() - 16_000; assert online === false; assert snapshot().comm.mqttConnected stays as-is (unused)

test('esp32 timeout honors ESP32_TELEMETRY_TIMEOUT_SEC', ...)
// config override { esp32TelemetryTimeoutSec: 5 }; atMs = Date.now() - 6_000 -> online false; -4_000 -> true
```

- [ ] **Step 2: Run to verify fails**

Run: `node --test backend/test/state.test.js`
Expected: FAIL — no `esp32` field / no `markEsp32Telemetry`.

- [ ] **Step 3: Implement** matching the interfaces exactly. `newZone` gains `esp32LastTelemetryAtMs: null` (it must survive snapshot's `JSON.stringify(zones)` — it does, as a number).

- [ ] **Step 4: Run tests**

Run: `node --test backend/test/state.test.js`
Expected: PASS, all prior state tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add backend/src/config.js backend/src/state.js backend/test/state.test.js
git commit -m "feat: ESP32 telemetry-freshness liveness in /api/state"
```

### Task 5: Command tracker with ack semantics

**Files:**
- Create: `backend/src/command_tracker.js`
- Test: `backend/test/command_tracker.test.js`

**Interfaces:**
- Produces: `makeCommandTracker({ ackTimeoutSec = 10, limit = 10, now = () => Date.now() })` returning:
  - `issued({ requestId, event, zone, actor, at })` → appends `{ requestId, event, zone, actor, status: 'PENDING', issuedAtMs: at, ackAtMs: null }` (newest at the end); returns the entry.
  - `acknowledgePending(at)` → for every `PENDING` entry with `issuedAtMs <= at` **and** `at - issuedAtMs <= ackTimeoutSec * 1000`, set `status = 'ACKNOWLEDGED'`, `ackAtMs = at`. Entries issued after the instantaneous `at`, or older than the window, are untouched (old ones wait for the sweeper). Returns count acknowledged.
  - `sweep(at)` → `PENDING` entries with `at - issuedAtMs > ackTimeoutSec * 1000` become `status = 'TIMED_OUT'`, `ackAtMs = null`. Returns count.
  - `snapshot()` → newest-first `Array` (max `limit`) of each entry as `{ requestId, event, zone, actor, status, issuedAt: ISO string, ackAt: ISO string | null }`.
- Semantic pins already covered by Review Focus line 2 and 5.

- [ ] **Step 1: Write the failing tests**

Use injected `now: () => fakeNow` for determinism:

```js
test('issued command is PENDING and snapshot is newest-first')
test('acknowledgePending acks a command issued before the telemetry and within window')
// at t=1000 issued; telemetry at t=6000 (ackTimeoutSec=10) -> ACKNOWLEDGED with ackAtMs=6000
test('telemetry arriving before any command acks nothing') // issue at t=7000 after ack call at t=6000 -> still PENDING
test('sweep times out pending after window; acknowledged ones untouched')
test('snapshot caps at limit and renders ISO timestamps')
```

- [ ] **Step 2: Run to verify fails**

Run: `node --test backend/test/command_tracker.test.js`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement** per interface. Simple array + filter; no deps.

- [ ] **Step 4: Run tests**

Run: `node --test backend/test/command_tracker.test.js`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/command_tracker.js backend/test/command_tracker.test.js
git commit -m "feat: esp32 command tracker with publish-vs-ack separation"
```

### Task 6: Wire tracker + liveness into ingest, control route, server/app

**Files:**
- Modify: `backend/src/ingest.js` (both ESP32 telemetry branches)
- Modify: `backend/src/routes/control.js:41-46` (esp32 command publish branch)
- Modify: `backend/server.js`, `backend/src/app.js` (optional dep), `backend/test/app_helpers.js`
- Modify: `backend/src/state.js` (snapshot adds `esp32Commands`)
- Test: `backend/test/ingest.test.js` (append), `backend/test/state.test.js` (append)

**Interfaces:**
- Produces: deps get optional `commandTracker`. In `server.js`: `const commandTracker = makeCommandTracker({ ackTimeoutSec: config.commandAckTimeoutSec });` created after config, passed to `makeIngest({ ..., commandTracker })` and into `createApp({ ..., commandTracker })`. In `state.js`: `state.setCommandTracker(commandTracker)` (server.js calls it right after creation; default null) — snapshot adds `esp32Commands: commandTracker ? commandTracker.snapshot() : []`.
- `ingest.js`: on a valid ESP32 telemetry (both the DEVICE_TELEMETRY and legacy branches), call `state.markEsp32Telemetry(zone)` and `commandTracker?.acknowledgePending(Date.now())`. Invalid/duplicate telemetry does **not** ack (invalid isn't evidence of a device doing work).
- `routes/control.js`: inside the `config.esp32Zone === check.value.zone` branch, after the publish: `commandTracker?.issued({ requestId: check.value.request_id, event: check.value.event, zone: check.value.zone, actor: req.user.username, at: Date.now() });`
- Neither calls when no tracker is wired or tracker is undefined.

- [ ] **Step 1: Write the failing tests**

`command_tracker.test.js` — integration-flavored additions using `app_helpers.buildDeps` (wiring only):

```js
test('valid esp32 telemetry records liveness and acks pending commands', ...)
// buildDeps with tracker injected; ingest.handle('railway/telemetry/esp32', validEnvelopeMessage);
// assert state.snapshot().esp32.online === true and tracker snapshot shows issued command ACKNOWLEDGED
test('invalid esp32 telemetry acks nothing') // duplicate request_id ingest -> tracker unchanged, esp32 still offline if never valid
test('issuing an esp32-zone control command records a PENDING ledger entry', ...)
// POST /api/control via withServer targeting esp32Zone -> snapshot().esp32Commands[0].status === 'PENDING'
```

Write with the same auth/setup utilities the existing app-level tests use (follow `app.test.js` / `ingest.test.js` patterns for building a valid telemetry envelope and login headers).

- [ ] **Step 2: Run to verify fails**

Run: `node --test backend/test/command_tracker.test.js`
Expected: FAIL — wiring absent.

- [ ] **Step 3: Implement** per interfaces (optional-chained everywhere; app.js forwards `deps` untouched, no signature change needed beyond passing tracker through `deps`).

- [ ] **Step 4: Run tests**

Run: `node --test backend/test/command_tracker.test.js backend/test/ingest.test.js`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/ingest.js backend/src/routes/control.js backend/server.js backend/src/state.js backend/test/command_tracker.test.js
git commit -m "feat: wire esp32 liveness and command ack tracking end to end"
```

### Task 7: Godot auto-wildlife off by default

**Files:**
- Modify: `godot/config.cfg:8`

**Interfaces:** none. `wildlife_behaviour.gd:48` already reads `[simulation] auto_wildlife`; demos get no automatic animal spawns, and `auto_wildlife=true` still enables realistic runs. Manual wildlife (commands + camera) is untouched.

- [ ] **Step 1: Set `auto_wildlife=false`** in `[simulation]`.
- [ ] **Step 2: Sanity check no other simulation key depends on the value**: `grep -rn "auto_wildlife" godot/src`.
- [ ] **Step 3: Commit**

```bash
git add godot/config.cfg
git commit -m "feat: disable auto wildlife spawns for demo runs by default"
```

### Task 8: Web communicator-kernel panel

**Files:**
- Modify: `web/src/App.tsx` (types at `~91-160`, panel JSX near the events card, `~700-745`)
- Build check: `npm --prefix web run build`

**Interfaces:**
- Consumes: `/api/state` fields from Tasks 4–6: `esp32?: { zone: string; online: boolean; lastSeenSec: number|null; sensorHealthy: boolean; nearAnimal: boolean }` and `esp32Commands?: Array<{ requestId: string; event: string; zone: string; actor: string; status: 'PENDING'|'ACKNOWLEDGED'|'TIMED_OUT'; issuedAt: string; ackAt: string|null }>`. Add both to the `State` type as optional.
- Produces: a card rendered next to the existing events card using the same card/badge className patterns already in the file; **no new props, no new fetch**.

- [ ] **Step 1: Extend types** with the two optional fields above.
- [ ] **Step 2: Add the panel** "Communicator Kernel — Wokwi ESP32":
  - Status dot + label: `esp32?.online ? 'ONLINE' : 'OFFLINE'`; when `lastSeenSec !== null`, append `· last seen ${lastSeenSec}s ago`; when null, `· no telemetry yet`.
  - Rows: `sensorHealthy` → `sensors OK`/`SENSOR FAULT`, `nearAnimal` → `near animal: yes/no`, topic `railway/telemetry/esp32` (zone from `esp32.zone`, default `zone1`).
  - Commands list (top 5 of `esp32Commands ?? []`): `event`, `zone`, time from `issuedAt` (local), badge colored per status: PENDING amber, ACKNOWLEDGED green, TIMED_OUT red; guard every field with `??` so a backend without the new fields renders an empty, non-crashing panel.
- [ ] **Step 3: Run build**

Run: `npm --prefix web run build`
Expected: PASS (0 type errors)

- [ ] **Step 4: Commit**

```bash
git add web/src/App.tsx
git commit -m "feat: communicator kernel panel for Wokwi ESP32 in web dashboard"
```

### Task 9: Full gate run + live smoke

**Files:** none (verification only)

- [ ] **Step 1: Full backend suite** — `npm --prefix backend test`. Expected: all pass (`141+` plus new tests). If MQTT-dependent suites fail in the sandbox, re-run outside the sandbox as established previously.
- [ ] **Step 2: Web build** — `npm --prefix web run build`. Expected: PASS.
- [ ] **Step 3: Live smoke (outside sandbox):**
  1. Broker `rdt-test-mqtt` up; start backend on 3001 with `MQTT_URL=mqtt://127.0.0.1:1883`.
  2. Login (`operator` / `operator-dev-pass`), `GET /api/state` → `esp32` present (`online: false` until Wokwi runs).
  3. Start Wokwi (esp32 client) → within ~15 s `esp32.online` flips true.
  4. `POST /api/control` targeting zone1 → `esp32Commands[0]` appears PENDING, then ACKNOWLEDGED on next ESP32 telemetry.
  5. Trigger a meet hold (or wait for one) and confirm release restores 48 with a `SPEED_RESTORED_FALLBACK` event in `/api/events`.
- [ ] **Step 4: Update the spec's status line** to record the live smoke results; commit with the verification note.
