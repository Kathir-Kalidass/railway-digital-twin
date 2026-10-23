# Design — Demo-calm train ops + ESP32 communicator kernel panel

Date: 2026-10-23
Status: Approved in conversation (user picked A1 + B1 with refinements below)

> **Implementation closed 2026-10-23.** Plan: `docs/superpowers/plans/2026-10-23-demo-calm-esp32-kernel.md`.
> Gates: backend suite 166/166; web build PASS. Live smoke (backend :3001 + docker
> broker `rdt-test-mqtt`): `esp32` offline at boot → online after telemetry (lastSeenSec 2)
> → offline again after 34 s of silence; command issued → `PENDING` while the device was
> silent → `ACKNOWLEDGED` on matching telemetry → `TIMED_OUT` for a second command nobody
> answered; meet hold release restored T1 to 48 km/h and logged
> `SPEED_RESTORED_FALLBACK` (attemptedSavedKmh null) in `/api/events`, meet history shows
> `restoredKmh: 48 / HELD`. Auto-wildlife disabled in `godot/config.cfg` for demo runs.

## Intent and why

The web dashboard is hard to operate: trains stop "randomly" and stay held or
dead, because (1) Godot auto-spawns wildlife on a cooldown, (2) meet holds
restore a saved speed of `null`/0 when the operator never set a speed, and
(3) the wrong-line finisher has the same `null`/0 restore gap. Separately, the
Wokwi ESP32 — the system's communicator kernel — is invisible in the web UI.

Two goals:

1. **A — Tame stops/holds (A1).** Disable automatic wildlife by default for
   demos (manual wildlife testing still works); restore a safe 48 km/h
   fallback when a saved speed is missing, logging the restoration as an
   event; keep the existing clear → reset → resume flow and fleet-resume
   button.
2. **B — ESP32 kernel panel (B1).** Surface the Wokwi ESP32 in the web
   dashboard through the backend's single existing MQTT connection. No second
   web→broker connection (B2 rejected), no new websocket relay (B3 rejected).

## Goals

- A1: `auto_wildlife` default off in demo config; env/config still turns it on.
- A1: every hold/finish/abort path restores speeds that are always finite and
  sensible; fallback = fleet cruise speed (48 km/h).
- A1: restoration events land in the backend event history so the UI shows why
  a speed changed.
- B: `/api/state` exposes ESP32 status: online/offline, seconds since last
  telemetry, sensorHealthy, nearAnimal, plus live command tracking.
- B: web panel "Communicator Kernel — Wokwi ESP32" with status dot, telemetry
  readout, and per-command state (pending / acknowledged / timed out).

## Non-goals

- No Demo/Realistic simulation toggle in the UI (A2 rejected for now).
- No direct web→MQTT websocket subscription (B2) and no websocket relay (B3).
- No changes to the two-frame camera confirmation rules or hazard semantics.

## Anti-goals (what would make this a failure)

- Masking genuine hazards: confirmed wildlife must still stop trains.
- A command marked "acknowledged" without matching ESP32 evidence.
- ESP32 shown "online" just because the backend's MQTT connection is alive.

## Constraints (user-pinned implementation details)

1. **Liveness = telemetry freshness, not broker connection.** ESP32 status is
   `online` only when the last accepted `railway/telemetry/esp32` message is
   younger than a configurable timeout (`ESP32_TELEMETRY_TIMEOUT_SEC`, default
   15 s — generous over a Wokwi heartbeat). Broker-connected with stale
   telemetry ⇒ offline.
2. **Acknowledgements are separate from publishes.** A backend MQTT publish is
   not an ack. A command becomes `ACKNOWLEDGED` only on matching ESP32
   evidence (telemetry elevated to `backendContextFresh` / echo of that
   command's `request_id` provenance after the publish), and `TIMED_OUT` after
   a configurable timeout if such evidence never arrives.
3. **Speed restore always logs.** When a saved speed is missing/invalid, the
   48 km/h fallback restoration is recorded as an event
   (`SPEED_RESTORED_FALLBACK`) in the event/history stream.

## Approaches considered

- **A1 (chosen):** demo-safe defaults + robust restore. Least machinery,
  fixes what actually breaks the operator loop. Trades away the spontaneous
  auto-wildlife drama unless re-enabled by config.
- **A2 (rejected):** UI Demo/Realistic switch — more moving parts
  (backend endpoints + Godot config hand-off), slower to land.
- **A3 (rejected):** only fix restores — animals keep ambushing demos.
- **B1 (chosen):** backend tracks liveness/health/acks over its single MQTT
  connection; web renders from `/api/state`. Zero new connections.
- **B2 (rejected):** web subscribes to MQTT over ws:9001 directly — second
  connection to secure/sync.
- **B3 (rejected):** backend websocket relay — most infrastructure, no need
  at current telemetry rate.

## Design — the parts decided

### Backend

- `config.js`: add `esp32TelemetryTimeoutSec` (env
  `ESP32_TELEMETRY_TIMEOUT_SEC`, default 15) and `commandAckTimeoutSec`
  (env `COMMAND_ACK_TIMEOUT_SEC`, default 10).
- `state.js`: track per-ESP32 `lastTelemetryAt` (wall-clock, set in
  `ingest.js` when a valid telemetry message is accepted), `sensorHealthy`,
  `nearAnimal`, and add `esp32: { online, lastSeenSec, sensorHealthy,
  nearAnimal }` to zone state exposed by `/api/state`.
- `state.js`: add a command ledger — on `railway/commands/esp32` publish
  (`routes/control.js` path), record `request_id`, issued time,
  command summary, status `PENDING`. On evidence of acceptance (ingest of
  telemetry after a matching command was dispatched — the ESP32 only
  elevates `backendContextFresh` and applies outputs after it accepts), mark
  `ACKNOWLEDGED`. A sweeper marks `PENDING` commands older than
  `commandAckTimeoutSec` as `TIMED_OUT`. Expose the recent ledger (last ~10)
  in `/api/state`.
- `meets.js` + `wrong_line.js`: introduce a shared `restoreSpeed(train,
  savedKmh, { reason })` helper (in a small util module): if `savedKmh` is a
  finite number > 0, use it; else use fleet cruise speed (48) and emit a
  `SPEED_RESTORED_FALLBACK` event through the bus with train id, reason
  (MEET_HOLD_RELEASE / WRONG_LINEFinish variant), and the restored speed.
- Demo config: `godot/config.cfg` `[simulation] auto_wildlife=false`
  (config knob already exists in `wildlife_behaviour.gd`); default stays
  documented as off for demos, on for realistic runs.

### Web (`web/src/App.tsx` + types)

- TypeScript: extend the state types with `esp32` and the command ledger.
- New card/section: "Communicator Kernel — Wokwi ESP32": status dot
  (online/offline with seconds-since-last-telemetry), sensorHealthy,
  nearAnimal, and the recent command list with per-command
  PENDING/ACKNOWLEDGED/TIMED_OUT badges.
- State refresh already polls `/api/state`; panel reads from the same poll
  (no new connection). Poll cadence unchanged unless it proves sluggish.

### Tests (per existing contracts)

- `state.test.js`: liveness timeout boundary (online ← fresh, offline ←
  stale), ack lifecycle (PENDING → ACKNOWLEDGED on evidence, → TIMED_OUT on
  timeout), `SPEED_RESTORED_FALLBACK` event emitted.
- `meets.test.js`: releaseHold with null/0-saved speed restores 48 + logs.
- `wrong_line` tests: `finish()` paths restore 48 + log when saved speed
  missing.
- Existing contracts must stay green (two-frame confirmation, hazard clearing
  on `WILDLIFE_CLEARED`).

## What's left to the builder

- Exact wording/shape of ledger entries and the ESP32 panel layout — match
  existing UI card patterns in `App.tsx`.
- Whether ack evidence is a dedicated ledger flag or derived from telemetry
  arrival after a specific publish — implementer's call, subject to the pin:
  publish-only never counts as ack.
- Event-history surfacing of `SPEED_RESTORED_FALLBACK` in the UI (reuse the
  existing history/event list component if present).
