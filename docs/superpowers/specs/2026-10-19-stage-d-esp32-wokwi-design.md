# Stage D — ESP32 and Wokwi Controller Design

Date: 2026-10-19  
Status: Closed — implemented and accepted  
Parent design: [`2026-10-18-railway-digital-twin-enhancement-design.md`](./2026-10-18-railway-digital-twin-enhancement-design.md)  
Related designs: [`2026-10-19-stage-a2-block-signalling-design.md`](./2026-10-19-stage-a2-block-signalling-design.md), [`2026-10-19-stage-b-dashboard-design.md`](./2026-10-19-stage-b-dashboard-design.md), [`2026-10-19-stage-c-godot-digital-twin-design.md`](./2026-10-19-stage-c-godot-digital-twin-design.md), [`2026-10-19-stage-e-integrated-delivery-design.md`](./2026-10-19-stage-e-integrated-delivery-design.md)

> **Safety boundary:** The ESP32 and Wokwi project are an educational
> controller demonstration. LEDs and buzzer are not railway signalling or
> safety equipment. Do not connect them to live infrastructure.

## 1. Purpose and outcome

Upgrade the existing ESP32 sketch to use device-scoped authenticated MQTT,
report validated sensor telemetry, respond to backend-forwarded commands,
and represent local and backend conditions with the existing LEDs and
buzzer. The firmware must remain responsive through network loss and must
never treat a lost connection as evidence that a hazard cleared.

Stage D is complete when firmware/build and contract checks pass, broker ACLs
are verified, backend ingestion is zone-scoped and validated, and Wokwi or
physical checks are documented accurately.

## 2. Scope, identity, and authority

The first implementation supports one configured controller identity,
`esp32`, mapped to one configured zone (`zone1` or `zone2`). Multiple
physical units require unique broker users/passwords, client identities,
explicit ACL entries, and per-device dashboard presentation; they are not
implicitly supported by reusing one credential.

- The backend remains authoritative for accepted control, state, and signals.
- Device-local input changes are telemetry observations, not control
  commands.
- The dashboard sends controls through authenticated backend REST only.
- The ESP32 may consume backend-forwarded commands to update its demo output,
  but cannot publish commands or override an active local fault/wildlife
  input.
- The device must not choose its zone based on an incoming MQTT payload.

Stage A2 (multi-train, block signalling) does **not** change the device
contract: the ESP32 consumes only its configured **zone**-level state/signal
(read from `railway/state` or `railway/zoneN/signal`) and never per-block
signalling (`railway/signal/{blockId}`). Its telemetry continues to flow
through normal ingestion, now normalized to `state.setSensor(zone, healthy)`
after the A2 split of `applyTelemetry` (§6). The device remains a single
permit that publishes `railway/telemetry/esp32` and reads
`railway/commands/esp32`; A2 added no permissions for this identity.

## 3. MQTT contracts

### 3.1 Device telemetry

Publish non-retained telemetry only to `railway/telemetry/esp32`. The
configured zone is fixed in firmware and must match the topic's device
assignment at the backend.

```json
{
  "request_id": "esp32-boot-sequence",
  "zone": "zone1",
  "event": "DEVICE_TELEMETRY",
  "timestamp": "2026-10-19T12:00:00.000Z",
  "source": "esp32",
  "payload": {
    "device": "esp32",
    "sensorHealthy": true,
    "wildlifeDetected": false,
    "uptimeMs": 12345
  }
}
```

`request_id` is unique per device boot and sequence. Telemetry is not a user
command and grants no authority. Backend ingestion validates shape, source,
zone, freshness, and values before applying sensor state. During migration,
the backend may accept the currently emitted flat telemetry format as a
compatibility path; the final firmware emits the envelope above.

### 3.2 Command subscription

Subscribe only to `railway/commands/esp32`. Validate topic, zone, event,
required envelope fields, timestamp freshness, and supported values. Ignore
malformed, stale, duplicate, or out-of-zone commands. Command messages are
not retained. Backend forwards a command only after an authenticated REST
action has been validated, accepted, state-applied, and audited, and only if
the command zone matches the device's configured zone.

The device identity has only these broker permissions:

```text
user esp32
topic write railway/telemetry/esp32
topic read railway/commands/esp32
```

It cannot publish commands, state, signals, events, or alerts, nor read
another client's topics. Do not broaden the ACL with `railway/#`.

## 4. Firmware behavior

### 4.1 Structure and runtime

Separate concerns into small functions/modules for configuration, Wi-Fi
lifecycle, MQTT lifecycle, debounced input sampling, output application,
command validation, telemetry serialization, and serial diagnostics. Keep
the loop non-blocking: Wi-Fi/MQTT retry behavior must not prevent periodic
button sampling or output updates.

On boot, set the visual outputs to the restrictive indication and sample
local inputs before reporting health. Debounce active-high buttons; publish
on stable state changes and a periodic health heartbeat (default 1.5
seconds). Use a stable unique client ID and bounded reconnect backoff.

### 4.2 Output precedence

The demo output decision is:

1. Active local wildlife input or local fault input → restrictive LED/buzzer.
2. Stale/lost backend communication → restrictive communication indication.
3. Otherwise → render the last valid backend state/signal for the configured
   zone.

GREEN is permitted only for healthy local inputs and a current,
non-restrictive backend state. A received command cannot override active
local wildlife/fault input. These outputs are illustrative only and are not
an interlock or certified fail-safe.

On disconnect, preserve hazard/fault observations, indicate communication
loss, and do not infer that the system is clear. On reconnect, resubscribe,
wait for fresh backend state/command context as applicable, and publish a
fresh local telemetry sample. Never retain telemetry or queue old commands
for later replay.

### 4.3 Time and freshness strategy

The firmware must emit a timestamp that the backend can evaluate under its
freshness policy. Do not emit an epoch/zero timestamp and silently treat it
as fresh. During implementation planning, choose and test one strategy:

- obtain UTC from a configured time source and hold telemetry until the clock
  is valid; or
- implement an explicit boot/session handshake that lets the backend
  associate monotonic uptime/sequence with server time.

Include uptime and boot/session identity in either case. The selected design
must specify behavior when the device starts offline, loses its clock, or
reboots. Stale telemetry is rejected or explicitly marked invalid by the
backend.

## 5. Configuration, secrets, and hardware

Remove hard-coded Wi-Fi, broker host, username, and password from
`railway_controller.ino`. Supply local secrets through an ignored
`secrets.h` or protected PlatformIO environment, and commit only a
`secrets.example.h` with placeholders. Never log credentials or full
payloads.

- Wokwi's guest Wi-Fi is a development option, not a route to a broker on
  `localhost`. Configure a broker host reachable from the simulator/device.
- `localhost` on a physical ESP32 refers to that device, not the developer's
  machine.
- Do not re-enable anonymous broker access to work around reachability.
- External/non-local use requires a separate TLS transport, secret
  provisioning, and credential-rotation design; this stage does not claim
  production readiness.

Keep the current GPIO mapping unless firmware, diagram, and tests are changed
together:

| Function | GPIO |
|---|---:|
| Red LED | 25 |
| Green LED | 26 |
| Buzzer | 27 |
| Wildlife input | 33 |
| Fault input | 32 |

Update `esp32/diagram.json`, `platformio.ini`, and `libraries.txt` together
when wiring or dependencies change.

## 6. Backend integration

Extend `backend/src/ingest.js` (or a narrowly scoped telemetry adapter) to
normalize the envelope and validate it before state mutation. Verify device
identity and configured zone; reject malformed, stale, duplicate, and
out-of-zone updates with repository-standard logging/event handling. Do not
silently apply a missing sensor value as healthy. After Stage A2, an accepted
telemetry sample must call the narrow setter `state.setSensor(zone, healthy)`
(and `state.setWildlife` for wildlife observations), **not** the removed merged
`applyTelemetry`; ingestion must never mutate train/block state.

For accepted REST controls, forward to `railway/commands/esp32` only when
the configured device zone matches the action zone. Publish only after the
normal validation, state transition, audit, and zone command publication.
Rejected, unauthorized, invalid, or other-zone actions must never be
forwarded.

## 7. Verification and acceptance

### Automated checks

- PlatformIO build succeeds for the configured ESP32 target.
- Wokwi diagram parses and pin mapping matches the firmware.
- Host-side tests/fixtures cover telemetry serialization, sequence behavior,
  debounce/state transitions, output precedence, command validation, and
  reconnect scheduling.
- Broker ACL tests prove allowed device publish/subscribe and denied
  attempts to publish commands/state/signals or access other clients' topics.
- Backend tests cover valid/malformed/stale telemetry, zone isolation,
  state updates (`setSensor`/`setWildlife`), expiry/clock behavior, and command
  forwarding only after an accepted same-zone REST action.
- A2 regression: a telemetry sample changes only the configured zone's sensor/
  wildlife state and never any `trains[]`/`blocks[]` occupancy or aspect.
- Rejection-path tests assert no device command is forwarded for invalid,
  unauthorized, duplicate, failed-transition, or other-zone requests.

### Manual Wokwi/physical checklist

1. Boot and verify restrictive startup output until current state is known.
2. Press and release each button; verify debounce, local output, telemetry,
   backend state, and dashboard display.
3. Issue authorized same-zone control from dashboard; verify forwarded
   response and that local active faults still dominate.
4. Try out-of-zone control and verify no device command is delivered.
5. Disconnect broker/network, exercise inputs, and verify no blocking and no
   false-clear/false-green behavior; reconnect and verify fresh telemetry.
6. Verify serial output contains useful diagnostics but no credentials.

Record whether each check was run in Wokwi, on physical hardware, or not run.
Local Docker broker success does not prove Wokwi internet reachability.
