# Stage D — ESP32 / Wokwi Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the ESP32 sketch to device-scoped authenticated MQTT with validated telemetry, safe output precedence, a freshness strategy, and backend command forwarding — and prove it with host-side tests, a PlatformIO build, and broker ACL checks.

**Architecture:** Split pure logic (telemetry serialization, output precedence, command validation, debounce) into host-testable headers under `esp32/src/`, and keep the Arduino/`main` glue thin. A PlatformIO `native` environment runs Unity tests on the host; the `esp32dev` environment builds the firmware. The backend gains envelope normalization in `ingest.js` and same-zone command forwarding to `railway/commands/esp32` after an accepted REST action.

**Tech Stack:** Arduino framework for ESP32 (`espressif32`), `PubSubClient` (MQTT), `ArduinoJson` (envelope), Unity (host tests), PlatformIO; Node.js backend (`node:test`).

**Specs:** [`../specs/2026-10-19-stage-d-esp32-wokwi-design.md`](../specs/2026-10-19-stage-d-esp32-wokwi-design.md), [`../specs/2026-10-19-stage-a2-block-signalling-design.md`](../specs/2026-10-19-stage-a2-block-signalling-design.md)

## Global Constraints

- Device identity `esp32` has only: `write railway/telemetry/esp32`, `read railway/commands/esp32`. No broad `railway/#`. No anonymous access workarounds.
- The device **never** publishes commands, state, signals, events, or alerts, and never chooses its zone from a payload.
- Output precedence: local wildlife/fault → restrictive; stale/lost comms → restrictive comms indication; else last valid backend zone state. A received command cannot override an active local wildlife/fault input.
- Telemetry is non-retained; commands are non-retained; never queue/replay stale telemetry or old commands.
- No credentials in git: local secrets via `esp32/secrets.h` (ignored); commit `esp32/secrets.example.h` only. Logs never print credentials.
- Keep the existing GPIO mapping unless firmware, `diagram.json`, and tests change together: Red LED 25, Green LED 26, Buzzer 27, Wildlife input 33, Fault input 32.
- After Stage A2, accepted telemetry must call the narrow setter `state.setSensor(zone, healthy)` / `state.setWildlife` and must never mutate `trains[]`/`blocks[]`.
- Freshness: the device must not emit an epoch/zero timestamp and treat it as fresh.

## File Structure

- Create `esp32/src/output_logic.h` — pure output-precedence decision.
- Create `esp32/src/telemetry.h` — pure telemetry envelope serialization.
- Create `esp32/src/command_logic.h` — pure command-envelope validation → effect enum.
- Create `esp32/src/debounce.h` — pure debounce state.
- Create `esp32/secrets.example.h`; modify `.gitignore` to ignore `esp32/secrets.h`.
- Modify `esp32/railway_controller.ino` — thin glue using the headers.
- Modify `esp32/platformio.ini` — add `native` test env + `ArduinoJson`.
- Create `esp32/test/test_logic/test_logic.cpp` — Unity host tests.
- Modify `esp32/libraries.txt`, `esp32/diagram.json` if wiring changes (it should not).
- Modify `backend/src/ingest.js` — envelope normalization + `setSensor`.
- Modify `backend/src/routes/control.js` — forward accepted same-zone command to `railway/commands/esp32`.
- Modify backend tests: `backend/test/ingest.test.js` (or equivalent), `backend/test/control_routes.test.js`.

---

### Task 1: Secrets and configuration extraction

**Files:**
- Create: `esp32/secrets.example.h`
- Modify: `.gitignore`
- Modify: `esp32/railway_controller.ino`

**Interfaces:**
- Produces: `secrets.h` defining `WIFI_SSID`, `WIFI_PASSWORD`, `MQTT_HOST`, `MQTT_PORT`, `MQTT_USER`, `MQTT_PASS`, `DEVICE_ID = "esp32"`, `DEVICE_ZONE = "zone1"`.

- [ ] **Step 1: Write `esp32/secrets.example.h`**

```cpp
#pragma once
// Copy to secrets.h (git-ignored) and fill real values. Never commit secrets.
#define WIFI_SSID "Wokwi-GUEST"
#define WIFI_PASSWORD ""
#define MQTT_HOST "192.168.1.10"   // reachable from the device; never localhost
#define MQTT_PORT 1883
#define MQTT_USER "esp32"
#define MQTT_PASS "change-me"
#define DEVICE_ID "esp32"
#define DEVICE_ZONE "zone1"        // must match backend assignment
```

- [ ] **Step 2: Ignore real secrets**

Append to `.gitignore` (create the line if absent):

```text
esp32/secrets.h
```

- [ ] **Step 3: Include secrets in the sketch**

Replace the hard-coded `const char*` blocks at the top of `railway_controller.ino` with:

```cpp
#include "secrets.h"
```

and use `DEVICE_ID`/`DEVICE_ZONE` where the identity/zone are needed.

- [ ] **Step 4: Verify no secret is tracked**

Run: `git check-ignore esp32/secrets.h || true` and `git ls-files esp32 | grep -i secret` (expected: no `secrets.h`, only `secrets.example.h`).

- [ ] **Step 5: Commit**

```bash
git add esp32/secrets.example.h .gitignore esp32/railway_controller.ino
git commit -m "chore(esp32): extract secrets to ignored header with example"
```

---

### Task 2: Pure output precedence + debounce logic (host-tested)

**Files:**
- Create: `esp32/src/output_logic.h`, `esp32/src/debounce.h`
- Create: `esp32/test/test_logic/test_logic.cpp`
- Modify: `esp32/platformio.ini`

**Interfaces:**
- Produces: `enum class Output { RESTRICTIVE, COMM_LOSS, RENDER_BACKEND };` and
  `Output decide_output(bool local_wildlife, bool local_fault, bool comm_ok, bool backend_restrictive);`
  plus `struct Debouncer { bool update(bool raw, unsigned long now_ms); }` with a debounce interval constant.

- [ ] **Step 1: Add the native test env**

`esp32/platformio.ini`:

```ini
[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
monitor_speed = 115200
lib_deps =
    knolleary/PubSubClient@^2.8
    bblanchon/ArduinoJson@^7
build_src_filter = +<*> -<test/>

[env:native]
platform = native
test_framework = unity
build_flags = -std=gnu++17
test_build_src = no
```

- [ ] **Step 2: Write failing host tests**

`esp32/test/test_logic/test_logic.cpp`:

```cpp
#include <unity.h>
#include "output_logic.h"
#include "debounce.h"

void test_local_wildlife_dominates() {
  TEST_ASSERT_EQUAL(int(Output::RESTRICTIVE),
                    int(decide_output(true, false, true, false)));
}
void test_local_fault_dominates_command() {
  TEST_ASSERT_EQUAL(int(Output::RESTRICTIVE),
                    int(decide_output(false, true, true, false)));
}
void test_comm_loss_restrictive() {
  TEST_ASSERT_EQUAL(int(Output::COMM_LOSS),
                    int(decide_output(false, false, false, false)));
}
void test_backend_restrictive_rendered() {
  TEST_ASSERT_EQUAL(int(Output::RENDER_BACKEND),
                    int(decide_output(false, false, true, true)));
}
void test_debounce_ignores_bounce() {
  Debouncer d; TEST_ASSERT_FALSE(d.update(false, 0));
  TEST_ASSERT_FALSE(d.update(true, 10));   // within interval, ignored
  TEST_ASSERT_TRUE(d.update(true, 100));   // stable
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_local_wildlife_dominates);
  RUN_TEST(test_local_fault_dominates_command);
  RUN_TEST(test_comm_loss_restrictive);
  RUN_TEST(test_backend_restrictive_rendered);
  RUN_TEST(test_debounce_ignores_bounce);
  UNITY_END();
}
void loop() {}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd esp32 && pio test -e native`
Expected: FAIL to compile (`output_logic.h`/`debounce.h` missing).

- [ ] **Step 4: Implement the headers**

`esp32/src/output_logic.h`:

```cpp
#pragma once
enum class Output { RESTRICTIVE, COMM_LOSS, RENDER_BACKEND };

inline Output decide_output(bool local_wildlife, bool local_fault,
                            bool comm_ok, bool backend_restrictive) {
  if (local_wildlife || local_fault) return Output::RESTRICTIVE;
  if (!comm_ok) return Output::COMM_LOSS;
  return Output::RENDER_BACKEND;   // caller reads backend_restrictive for the lamp
}
```

`esp32/src/debounce.h`:

```cpp
#pragma once
static const unsigned long DEBOUNCE_MS = 40;
struct Debouncer {
  bool stable = false;
  bool last_raw = false;
  unsigned long last_change = 0;
  bool update(bool raw, unsigned long now_ms) {
    if (raw != last_raw) { last_raw = raw; last_change = now_ms; return stable; }
    if (raw != stable && (now_ms - last_change) >= DEBOUNCE_MS) stable = raw;
    return stable;
  }
};
```

- [ ] **Step 5: Run tests, expect pass**

Run: `cd esp32 && pio test -e native`
Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add esp32/src/output_logic.h esp32/src/debounce.h esp32/test/test_logic/test_logic.cpp esp32/platformio.ini
git commit -m "feat(esp32): host-tested output precedence and debounce"
```

---

### Task 3: Telemetry envelope + freshness strategy

**Files:**
- Create: `esp32/src/telemetry.h`
- Modify: `esp32/test/test_logic/test_logic.cpp`
- Modify: `esp32/railway_controller.ino`

**Interfaces:**
- Produces: `std::string build_telemetry(const char* device, const char* zone, const char* request_id, const char* isoTimestamp, bool clock_valid, bool wildlife, bool sensor_healthy, unsigned long uptime_ms);` emitting the §3.1 envelope.

**Chosen freshness strategy:** SNTP (`configTime`). The device sets `clockValid` once time exceeds a sane epoch; it includes an ISO timestamp only when valid. When `clockValid` is false it emits `"clockValid": false` and the backend **rejects** clock-invalid/stale samples (never a false green). A unique `request_id` per boot (`DEVICE_ID + bootEsn`) plus a monotonic sequence is included.

- [ ] **Step 1: Add the failing test**

Append to `test_logic.cpp`:

```cpp
#include "telemetry.h"
#include <ArduinoJson.h>   // available in native via lib_deps? if not, string-assert instead
void test_telemetry_envelope() {
  std::string j = build_telemetry("esp32","zone1","esp32-boot-1",
    "2026-10-19T12:00:00.000Z", true, true, false, 12345);
  TEST_ASSERT_TRUE(j.find("\"zone\":\"zone1\"") != std::string::npos);
  TEST_ASSERT_TRUE(j.find("\"event\":\"DEVICE_TELEMETRY\"") != std::string::npos);
  TEST_ASSERT_TRUE(j.find("\"clockValid\":true") != std::string::npos);
}
void test_telemetry_clock_invalid() {
  std::string j = build_telemetry("esp32","zone1","esp32-boot-1","",false,false,true,50);
  TEST_ASSERT_TRUE(j.find("\"clockValid\":false") != std::string::npos);
}
```

Register both `RUN_TEST(...)` calls in `setup()`.

- [ ] **Step 2: Run to verify it fails**

Run: `cd esp32 && pio test -e native`. Expected: FAIL (`telemetry.h` missing).

- [ ] **Step 3: Implement `telemetry.h`**

Serialize with plain `snprintf`/`std::string` (no ArduinoJson dependency in the pure header) so it compiles on `native`:

```cpp
#pragma once
#include <string>
#include <cstdio>

inline std::string build_telemetry(const char* device, const char* zone,
    const char* request_id, const char* isoTimestamp, bool clock_valid,
    bool wildlife, bool sensor_healthy, unsigned long uptime_ms) {
  char buf[320];
  std::snprintf(buf, sizeof(buf),
    "{\"request_id\":\"%s\",\"zone\":\"%s\",\"event\":\"DEVICE_TELEMETRY\","
    "\"timestamp\":%s,\"clockValid\":%s,\"source\":\"esp32\",\"payload\":{"
    "\"device\":\"%s\",\"sensorHealthy\":%s,\"wildlifeDetected\":%s,\"uptimeMs\":%lu}}",
    request_id, zone,
    clock_valid ? (std::string("\"") + isoTimestamp + "\"").c_str() : "null",
    clock_valid ? "true" : "false", device,
    sensor_healthy ? "true" : "false", wildlife ? "true" : "false", uptime_ms);
  return std::string(buf);
}
```

- [ ] **Step 4: Use it in the sketch**

In `railway_controller.ino`: call `configTime(0, 0, "pool.ntp.org")` in `setup`; compute `clockValid = time(nullptr) > 1600000000`; build the payload with `build_telemetry(...)` and `mqtt.publish(TOPIC_TELEMETRY, payload.c_str())`. Hold the health heartbeat at 1.5 s and publish on stable input change.

- [ ] **Step 5: Run tests, expect pass**

Run: `cd esp32 && pio test -e native`. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add esp32/src/telemetry.h esp32/test/test_logic/test_logic.cpp esp32/railway_controller.ino
git commit -m "feat(esp32): validated telemetry envelope with clock validity"
```

---

### Task 4: Command validation and safe application

**Files:**
- Create: `esp32/src/command_logic.h`
- Modify: `esp32/test/test_logic/test_logic.cpp`
- Modify: `esp32/railway_controller.ino`

**Interfaces:**
- Produces: `enum class CmdEffect { NONE, WILDLIFE_SET, WILDLIFE_CLEAR, FAULT_SET, FAULT_RESTORE, RESET };`
  and `CmdEffect parse_command(const std::string& json, const char* expected_zone, unsigned long now_ms);` returning `NONE` for malformed, wrong-zone, stale, or duplicate commands.

- [ ] **Step 1: Add failing tests**

```cpp
#include "command_logic.h"
void test_command_rejects_other_zone() {
  std::string j = "{\"event\":\"WILDLIFE_DETECTED\",\"zone\":\"zone2\",\"timestamp\":\"2026-10-19T12:00:00.000Z\"}";
  TEST_ASSERT_EQUAL(int(CmdEffect::NONE), int(parse_command(j, "zone1", 0)));
}
void test_command_accepts_same_zone() {
  std::string j = "{\"event\":\"SENSOR_FAULT\",\"zone\":\"zone1\",\"timestamp\":\"2026-10-19T12:00:00.000Z\"}";
  TEST_ASSERT_EQUAL(int(CmdEffect::FAULT_SET), int(parse_command(j, "zone1", 0)));
}
void test_command_rejects_malformed() {
  TEST_ASSERT_EQUAL(int(CmdEffect::NONE), int(parse_command("{not json", "zone1", 0)));
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd esp32 && pio test -e native`. Expected: FAIL.

- [ ] **Step 3: Implement `command_logic.h`**

Use `ArduinoJson` for parsing in the sketch, but keep host testability by parsing with a minimal substring check in the header (documented as intentionally strict). Implement:

```cpp
#pragma once
#include <string>
enum class CmdEffect { NONE, WILDLIFE_SET, WILDLIFE_CLEAR, FAULT_SET, FAULT_RESTORE, RESET };

inline bool _has(const std::string& s, const char* k) { return s.find(k) != std::string::npos; }

inline CmdEffect parse_command(const std::string& json, const char* expected_zone,
                               unsigned long now_ms) {
  if (json.empty() || json.front() != '{' || json.back() != '}') return CmdEffect::NONE;
  std::string zq = std::string("\"zone\":\"") + expected_zone + "\"";
  if (!_has(json, zq.c_str())) return CmdEffect::NONE;   // reject wrong/missing zone
  if (_has(json, "WILDLIFE_DETECTED")) return CmdEffect::WILDLIFE_SET;
  if (_has(json, "WILDLIFE_CLEARED")) return CmdEffect::WILDLIFE_CLEAR;
  if (_has(json, "SENSOR_FAULT")) return CmdEffect::FAULT_SET;
  if (_has(json, "SENSOR_RESTORED")) return CmdEffect::FAULT_RESTORE;
  if (_has(json, "RESET")) return CmdEffect::RESET;
  return CmdEffect::NONE;
}
```

Note: staleness/duplicate rejection is enforced in the sketch (track `request_id` + timestamp freshness) before calling `parse_command`; the header stays pure for host tests.

- [ ] **Step 4: Apply in the sketch with precedence**

On message: validate topic == `railway/commands/esp32`, compute `parse_command`; on `RESET` only clear state if no active local wildlife/fault; `applyOutputs()` uses `decide_output(...)`. Never let a command clear an active **local** input.

- [ ] **Step 5: Run tests, expect pass**

Run: `cd esp32 && pio test -e native`. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add esp32/src/command_logic.h esp32/test/test_logic/test_logic.cpp esp32/railway_controller.ino
git commit -m "feat(esp32): validate and safely apply commands"
```

---

### Task 5: Non-blocking loop, reconnect backoff, no replay

**Files:**
- Modify: `esp32/railway_controller.ino`

**Interfaces:**
- Produces: a non-blocking `loop()` with bounded MQTT reconnect backoff (e.g., 1 s → 2 s → … capped 30 s), periodic input sampling, and periodic telemetry heartbeat; no `delay()` on the telemetry/command path.

- [ ] **Step 1: Restructure `loop()`**

Replace blocking `connectWiFi`/`connectMqtt` `while`/`delay` loops with non-blocking state: attempt reconnect only when `now - lastAttempt >= backoff`; cap backoff; reset backoff on success. Sample inputs every iteration with `Debouncer`. Publish telemetry on stable-change or 1.5 s heartbeat.

- [ ] **Step 2: Restrictive startup + comm-loss**

In `setup`, set outputs restrictive before any network. In `loop`, when `!mqtt.connected()` show the comm-loss indication (restrictive) and preserve wildlife/fault observations; never clear them on disconnect.

- [ ] **Step 3: On reconnect**

Resubscribe to `railway/commands/esp32` and publish a fresh telemetry sample; do **not** replay queued telemetry or old commands.

- [ ] **Step 4: Build firmware**

Run: `cd esp32 && pio run -e esp32dev`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add esp32/railway_controller.ino
git commit -m "feat(esp32): non-blocking loop with bounded reconnect"
```

---

### Task 6: Wokwi diagram and build config consistency

**Files:**
- Modify: `esp32/diagram.json` (only if wiring changed — it should not)
- Modify: `esp32/libraries.txt`
- Modify: `esp32/platformio.ini`

- [ ] **Step 1: Confirm pin mapping matches firmware**

Verify `diagram.json` uses GPIO 25/26/27 (LEDs/buzzer) and 33/32 (inputs) exactly as the firmware. If unchanged, leave it; if changed, update firmware and diagram together.

- [ ] **Step 2: Keep dependency lists in sync**

Set `esp32/libraries.txt` to `PubSubClient` and `ArduinoJson` to match `platformio.ini` `lib_deps`.

- [ ] **Step 3: Build + parse check**

Run: `cd esp32 && pio run -e esp32dev` (expected success) and confirm `diagram.json` is valid JSON: `python -c "import json;json.load(open('esp32/diagram.json'))"`.

- [ ] **Step 4: Commit**

```bash
git add esp32/diagram.json esp32/libraries.txt esp32/platformio.ini
git commit -m "chore(esp32): keep diagram and dependency config in sync"
```

---

### Task 7: Backend — telemetry envelope normalization

**Files:**
- Modify: `backend/src/ingest.js`
- Modify: `backend/test/ingest.test.js`
- Modify: `backend/test/app_helpers.js` (only if a helper is needed)

**Interfaces:**
- Consumes: `state.setSensor(zone, healthy)` and `state.setWildlife(zone, value)` (from Stage A2).
- Produces: `handle('railway/telemetry/esp32', envelope)` accepting both the new envelope (§3.1 of the D spec) and, during migration, the legacy flat format; validating `source === 'esp32'`, zone ∈ config.zones, `clockValid`, timestamp freshness, and boolean values; rejecting malformed/stale/out-of-zone samples with an event and **no** state mutation. Never mutates trains/blocks.

- [ ] **Step 1: Write failing tests**

Add to `backend/test/ingest.test.js` (using existing `fakeMqtt`/`buildDeps` helpers):

```js
test('esp32 envelope sets sensor via setSensor', () => {
  const { deps, state } = buildDeps();
  deps.ingest.handle('railway/telemetry/esp32', {
    request_id: 'esp32-boot-1', zone: 'zone1', event: 'DEVICE_TELEMETRY',
    timestamp: new Date().toISOString(), clockValid: true, source: 'esp32',
    payload: { device: 'esp32', sensorHealthy: false, wildlifeDetected: false, uptimeMs: 10 },
  });
  assert.equal(state.snapshot().zones.zone1.sensorHealthy, false);
});
test('esp32 out-of-zone rejected', () => {
  const { deps, state } = buildDeps();
  deps.ingest.handle('railway/telemetry/esp32', {
    zone: 'zone9', event: 'DEVICE_TELEMETRY', timestamp: new Date().toISOString(),
    clockValid: true, source: 'esp32', payload: { sensorHealthy: true },
  });
  assert.equal(state.snapshot().lastEvent, 'INVALID_TELEMETRY');
});
test('esp32 clock-invalid rejected', () => {
  const { deps, state } = buildDeps();
  deps.ingest.handle('railway/telemetry/esp32', {
    zone: 'zone1', event: 'DEVICE_TELEMETRY', timestamp: null, clockValid: false,
    source: 'esp32', payload: { sensorHealthy: true },
  });
  assert.equal(state.snapshot().lastEvent, 'INVALID_TELEMETRY');
});
test('esp32 telemetry never mutates trains', () => {
  const { deps, state } = buildDeps();
  const before = JSON.stringify(state.snapshot().trains || []);
  deps.ingest.handle('railway/telemetry/esp32', {
    zone: 'zone1', event: 'DEVICE_TELEMETRY', timestamp: new Date().toISOString(),
    clockValid: true, source: 'esp32', payload: { sensorHealthy: false },
  });
  assert.equal(JSON.stringify(state.snapshot().trains || []), before);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && npm test -- ingest`
Expected: FAIL on the new assertions.

- [ ] **Step 3: Implement normalization in `ingest.js`**

Replace the `railway/telemetry/esp32` branch: if the message has `event === 'DEVICE_TELEMETRY'`, validate envelope (source, zone, clockValid, freshness window, boolean payload fields), call `state.setSensor(zone, payload.sensorHealthy)` and optionally `state.setWildlife(zone, payload.wildlifeDetected)` (device identity may not own wildlife writes — keep sensor only unless the device is the configured wildlife source). On any failure, `state.markEvent('INVALID_TELEMETRY')` (or `bus.event`) and return without mutation. Retain the legacy flat-format branch for migration. The A2 change to `setSensor` (not `applyTelemetry`) is required here.

- [ ] **Step 4: Run tests, expect pass**

Run: `cd backend && npm test -- ingest`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/ingest.js backend/test/ingest.test.js
git commit -m "feat(backend): validate and normalize esp32 telemetry envelope"
```

---

### Task 7b: Backend — same-zone command forwarding

**Files:**
- Modify: `backend/src/routes/control.js`
- Modify: `backend/test/control_routes.test.js`

**Interfaces:**
- Produces: after an accepted `POST /api/control` (or `/api/speed` where applicable), publish the accepted command to `railway/commands/esp32` **only** when the device zone matches the command zone. Never forward rejected/unauthorized/duplicate/other-zone commands.

- [ ] **Step 1: Write failing tests**

```js
test('accepted zone1 command forwards to esp32 when zone matches', async () => {
  const { app, mqtt } = await withServer({ esp32Zone: 'zone1' });
  // authorize + issue a valid zone1 WILDLIFE_DETECTED via /api/control ...
  const pubs = mqtt.published.filter((p) => p.topic === 'railway/commands/esp32');
  assert.equal(pubs.length, 1);
  assert.equal(pubs[0].message.zone, 'zone1');
});
test('zone2 command does not forward to esp32 zone1', async () => {
  const { app, mqtt } = await withServer({ esp32Zone: 'zone1' });
  // issue a valid zone2 command ...
  assert.equal(mqtt.published.filter((p) => p.topic === 'railway/commands/esp32').length, 0);
});
test('rejected/duplicate command does not forward', async () => {
  // send an invalid or duplicate command; assert no commands/esp32 publish
});
```

Adapt helper names to the existing `app_helpers.js` (`buildDeps`, `withServer`, `fakeMqtt`).

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && npm test -- control_routes`
Expected: FAIL on the new assertions.

- [ ] **Step 3: Implement forwarding**

In `controlRouter`, after the successful `mqtt.publish(\`railway/commands/${zone}\`, ...)` and before responding, add:

```js
if (config.esp32Zone && config.esp32Zone === check.value.zone) {
  mqtt.publish('railway/commands/esp32', check.value);
}
```

Applied to the `/api/control` route; for `/api/speed`, forward only if the spec's demo requires device consumption of speed (default: do **not** forward speed; document this).

- [ ] **Step 4: Run tests, expect pass**

Run: `cd backend && npm test -- control_routes`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/control.js backend/test/control_routes.test.js
git commit -m "feat(backend): forward accepted same-zone command to esp32"
```

---

### Task 8: Verification — build, ACL, Wokwi checklist, docs

**Files:**
- Modify: `README.md`
- Modify: `esp32/diagram.json` (only if needed)

- [ ] **Step 1: Firmware build**

Run: `cd esp32 && pio run -e esp32dev`
Expected: success.

- [ ] **Step 2: Host tests**

Run: `cd esp32 && pio test -e native`
Expected: all pass.

- [ ] **Step 3: Backend regression + ACL**

Run: `cd backend && npm test` and `bash scripts/test-backend.sh`
Expected: pass; ESP32 ACL allow/deny cases pass (allowed telemetry write + command read; denied command/state/signal writes and other clients' topics).

- [ ] **Step 4: Document**

Add a README "ESP32 controller" subsection: identity/zone config, `secrets.h` setup, PlatformIO commands, the freshness strategy, and the Wokwi/device manual checklist from the D spec §7. Record each check as Wokwi / physical / not run.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs(esp32): document controller setup, tests, and checklist"
```

---

## Self-Review

**Spec coverage:** identity/authority (§2 → Tasks 1, 4); telemetry envelope + freshness (§3.1, §4.3 → Tasks 3, 7); command subscription + validation (§3.2 → Tasks 4, 7b); output precedence + disconnect behavior (§4.2 → Tasks 2, 5); config/secrets/hardware (§5 → Tasks 1, 6); backend integration (§6 → Tasks 7, 7b); build/ACL/contract checks (§7 → Tasks 2–4, 8). A2 alignment (setSensor, no train mutation) → Tasks 7.

**Placeholder scan:** No `TBD`/`TODO`. Task 7b's test bodies are described against the existing helpers rather than fully expanded; implementers must mirror the helper signatures in `backend/test/app_helpers.js` (concrete, discoverable). The `telemetry.h` header deliberately avoids ArduinoJson on the host to keep `native` compilation dependency-light; the sketch may use ArduinoJson where richer parsing is needed.

**Type consistency:** `decide_output`/`Output`, `Debouncer`, `build_telemetry`, `parse_command`/`CmdEffect` names are consistent across headers, tests, and the sketch. Backend forwarding uses the existing `mqtt.publish` interface and `config.esp32Zone` (add this config key in Task 7b, validated at startup).

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-19-stage-d-esp32-wokwi.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks.

**2. Inline Execution** — execute in-session with checkpoints (`superpowers:executing-plans`).

**Note:** Task 8 Step 4 (Wokwi) requires the Wokwi simulator or physical hardware and a broker reachable from it; record those checks as *not run* if unavailable. Local Docker broker success does not prove Wokwi internet reachability.
