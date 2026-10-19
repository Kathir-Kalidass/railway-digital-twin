# Stage E — Integrated Delivery and Operational Readiness Design

Date: 2026-10-19  
Status: proposed  
Parent design: [`2026-10-18-railway-digital-twin-enhancement-design.md`](./2026-10-18-railway-digital-twin-enhancement-design.md)  
Related designs: [`2026-10-19-stage-a2-block-signalling-design.md`](./2026-10-19-stage-a2-block-signalling-design.md), [`2026-10-19-stage-b-dashboard-design.md`](./2026-10-19-stage-b-dashboard-design.md), [`2026-10-19-stage-c-godot-digital-twin-design.md`](./2026-10-19-stage-c-godot-digital-twin-design.md), [`2026-10-19-stage-d-esp32-wokwi-design.md`](./2026-10-19-stage-d-esp32-wokwi-design.md)

> **Safety boundary:** The complete stack is an educational simulation, not
> railway safety equipment. Do not connect it to live signalling,
> infrastructure, or rolling stock.

## 1. Purpose and outcome

Make the completed backend, dashboard, Godot twin, and optional ESP32
controller reproducible to configure, run, verify, demonstrate, and recover.
This stage consolidates the previous stage contracts; it does not change
their authority model.

Stage E is complete when the documented local setup works from a clean
checkout, all applicable automated and manual gates have recorded evidence,
the demo is repeatable, and no real credentials or generated local state are
committed.

## 2. Integrated authority and data flow

- Dashboard operators issue commands through authenticated REST only.
- The backend validates, authorizes, applies, audits, and publishes accepted
  commands; it owns state, retained snapshots, **multi-train simulation, block
  occupancy, and per-block/per-zone signal aspects** (Stage A2). Clients render
  this authority and never derive a more permissive aspect.
- Dashboard MQTT credentials are read-only.
- Godot and ESP32 publish only their assigned telemetry and consume
  backend-owned state/commands. Neither device is an alternate command
  authority.
- Device-local inputs are observations; user operations remain authenticated
  and auditable.
- MQTT telemetry and command messages are non-retained. Backend state and
  authoritative signals are retained for reconnect synchronization.
- On disconnect, clients mark last-known state stale and do not infer hazard
  clearance. Reconnect reconciles from authoritative state before fresh
  telemetry.

Preserve least-privilege per-client ACLs. Never solve connectivity problems
by enabling anonymous access or granting a broad `railway/#` permission.

## 3. Reproducible local setup

Document one supported local developer path:

1. Install required Docker/Compose and language runtimes/SDKs, listing tested
   versions.
2. Copy `.env.sample` to ignored `.env`; set distinct development values for
   broker, JWT, and seeded users.
3. Generate the Mosquitto password file using `scripts/mosquitto_setup.sh`.
4. Start services using `scripts/dev-up.sh`.
5. Wait for broker authentication, backend health/MQTT readiness, and web
   startup. Readiness must report dependency failure, not success-shaped
   fallback.
6. Configure Godot using ignored `godot/config.cfg` from its sample. For
   optional ESP32/Wokwi, configure local secrets and a broker address
   reachable from that device/runtime.
7. Run backend tests, web build, broker ACL checks, and the integrated demo.
8. Stop with documented Docker Compose commands.

Keep SQLite data in the existing named volume. Explain safe backup and
intentional reset procedures, including exactly which data is affected.
Never delete unrelated volumes or user data as part of setup/cleanup.

## 4. Configuration and security documentation

Maintain samples with placeholders only:

- `.env.sample`
- `godot/config.cfg.sample`
- `esp32/secrets.example.h`

README and operational documentation must explain:

- Services, ports, tested runtimes, dependency installation, startup/shutdown,
  health URLs, and readiness expectations.
- Client identity and ACL matrix, exact topic ownership, and how to generate
  and rotate local credentials.
- Docker-host, Godot, Wokwi, and physical-device networking. State
  explicitly that `localhost` on ESP32 refers to the device itself.
- Broker/backend/dashboard/Godot/ESP32 diagnostics and safe recovery steps.
- How to identify stale state, restore connectivity, and recover from an
  active sensor fault without bypassing backend reset validation.
- Educational-only boundary, illustrative braking model, Wokwi network
  limitations, and missing TLS/production credential provisioning.

Do not call dashboard credentials embedded in a browser bundle production
secrets. The local dashboard broker identity remains read-only. External
access is unsupported until TLS/WSS and credential provisioning are designed
and implemented separately.

## 5. Repeatable demonstration

The demo must be deterministic enough to repeat and must explain every state
change:

1. Start from normal state; show both zones, green signals, healthy sensors,
   broker/backend/device connection indicators, and the **double-track loop
   with blocks and a station**.
2. **Multi-train operations (A2):** show ≥2 trains circulating on `UP`/`DOWN`
   lines, a meet/pass at the station (crossover), and per-block signal
   progression (`GREEN`→`YELLOW`→`RED` guarding the block ahead of a train).
3. Trigger wildlife in Zone 1 through Godot or ESP32 telemetry. Verify
   backend state, applicable events/alerts, dashboard update, simulated
   braking, and restrictive Zone 1 blocks/signal.
4. Verify Zone 2 remains isolated and displays only the backend-calculated
   aspect (including caution when applicable).
5. Clear the hazard; show recovery remains required; issue authorized
   dashboard reset and verify normal state.
6. Trigger sensor fault; verify restrictive indication and reset rejection.
   Restore the sensor and reset through the dashboard.
7. Change a zone (or per-train) target speed in the dashboard and show Godot's
   target, current simulated speed, and illustrative stopping-distance
   estimate.
8. Disconnect/reconnect the broker; show offline/stale status, no stale
   command replay, and retained-state reconciliation (trains resume without
   visible teleportation).
9. Demonstrate roles: viewer cannot control or read admin audit; operator can
   control but cannot read admin audit; admin can read audit.
10. Run the Godot safety and ops scenarios and the cinematic reel (Stage C2),
    confirming they trigger only Godot-local wildlife observations while all
    authority-changing actions come from the dashboard.

Harden `scripts/demo-scenarios.sh`: use strict HTTP status and response
validation, unique request IDs, actionable diagnostics, and safe cleanup in a
trap only where cleanup is valid. It must not assume success because a
substring appears in a response. Document state mutated by the script and
provide a non-destructive mode where feasible.

## 6. Verification gates and evidence

| Gate | Required evidence |
|---|---|
| Backend regression | `cd backend && npm test`; auth, RBAC, replay, audit, state, MQTT, ACL, and ingestion tests pass. |
| Block signalling (S0/A2) | Occupancy/aspect derivation, sim determinism, layered zone signals, expanded state shape, `/api/speed` per-train, and `/api/event` returns `404`. |
| Dashboard | `cd web && npm run build`; verify Stage B role-gating, live feed, health, per-train/block views, and control behavior. |
| Broker | Fresh setup rejects anonymous connections; all client ACL allow/deny cases pass (incl. Godot denied `railway/zoneN/train` write and allowed `railway/signal/+` read). |
| Godot | Headless project load plus Stage C1 correctness and C2 visual/animation/telemetry/reconnect checklist. |
| ESP32 | PlatformIO compile plus Stage D contract tests and Wokwi/device checklist. |
| Integrated system | Clean startup, readiness, full demo, broker reconnect, and shutdown verified. |
| Documentation | A second operator follows setup and recovery steps using only committed docs and local secret samples. |

Record exact commands, results, and environment. Mark manual tests not run
when unavailable; do not claim a Wokwi, hardware, or Godot check passed when
it was not executed.

## 7. Release packaging and repository hygiene

Before final acceptance:

- Verify ACLs after every topic/config change; retain exact per-client
  permissions.
- Review tracked files for `.env`, Mosquitto password files, Godot config,
  ESP32 secrets, SQLite WAL/SHM files, and other generated/local state. Do
  not remove user data as a cleanup shortcut.
- Ensure scripts invoked directly are executable, fail clearly on missing
  prerequisites, and produce actionable errors.
- Ensure project paths are repository-relative and no developer-specific
  absolute path is required.
- Verify `godot/assets/CREDITS.md` accounts for **every** imported asset
  (model, texture, HDRI, audio) with license name + URL, and that no asset with
  an unclear or non-permissive license is tracked. Flag large media before
  committing and prefer repo-size-appropriate sources.
- Update architecture/data-flow diagrams to show backend command authority,
  multi-train/block signalling, and dashboard read-only MQTT.
- Link Stage A, B, C, D, and E specifications and demo instructions from
  the README.

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Demo state is left dirty between runs | Define initial/reset procedure; use unique request IDs; only perform safe cleanup after confirming hazards are clear. |
| One successful component check is mistaken for end-to-end readiness | Maintain separate backend, dashboard, broker, Godot, device, and integrated gates. |
| Wokwi cannot reach local broker | Test early; document a reachable authenticated broker; do not enable anonymous access. |
| Local credentials reach version control | Use ignored secret files, placeholder-only samples, and a tracked-file review before delivery. |
| Demo is mistaken for safety equipment | Keep the disclaimer in README, Godot HUD, firmware, and design documentation; avoid operational claims. |
| Visual detail reduces performance | Prioritize core scene, batch repeated meshes, cap particles, auto tier-knockdown, and record the tested machine/resolution. |
| Hero/ambient asset licensing or availability blocks delivery | CC0/CC-BY only, `CREDITS.md` manifest, asset-optional procedural fallback so CI and headless checks never depend on assets. |
| Local development defaults are used externally | Mark defaults dev-only; state that external deployment requires separate TLS/WSS, secret provisioning, and rotation work. |

## 9. Acceptance

Stage E passes when:

- A fresh operator can configure and start the stack using documented steps.
- All applicable verification gates pass with evidence and unavailable manual
  checks clearly identified.
- The complete multi-train/block-signalling, role, hazard, recovery, speed,
  and reconnect demo is repeatable.
- Every imported asset is license-verified and recorded, or replaced by an
  asset-optional procedural fallback.
- All client permissions remain least-privilege and no anonymous access is
  required.
- No real secrets or unintended local state are tracked.
- Documentation links the separate stage designs and accurately states the
  system's simulation-only limitations.
