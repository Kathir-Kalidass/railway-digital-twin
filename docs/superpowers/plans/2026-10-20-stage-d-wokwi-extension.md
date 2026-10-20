# Stage D — Wokwi ESP32 IoT Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing Wokwi ESP32 node from LED/buzzer/inputs into a full multi-sensor IoT device — ultrasonic, PIR and vibration sensing with LED, buzzer, **servo barrier** and **OLED** status — all over WiFi/MQTT, with pure logic unit-tested on the host.

**Architecture:** Keep the existing split: dependency-free pure logic in `esp32/src/*.h` (host-testable with PlatformIO `native`), hardware glue in `esp32/railway_controller.ino`. New sensors feed a pure `Sensors` fusion; new actuators (`Servo`, `OLED`) are driven by a pure `ActuatorState` derivation. New telemetry fields are appended to the existing envelope.

**Tech Stack:** PlatformIO (`espressif32`/`arduino`), PubSubClient, ArduinoJson 7, Unity host tests, Wokwi (`HC-SR04`, PIR, potentiometer-as-vibration, servo, SSD1306 OLED).

**Spec:** `docs/superpowers/specs/2026-10-20-stage-c-libretrainsim-wildlife-design.md` (§11)

## Global Constraints

- **Coordination required:** `esp32/**` is actively owned by a concurrent actor on `master`. Before editing, `git pull --rebase` and check `git log -5 -- esp32/`. All changes are **additive**: do not rewrite existing topics, payload keys, or the `output_logic`/`command_logic` contracts.
- Existing topics are fixed: `railway/telemetry/esp32` (publish), `railway/commands/esp32` (subscribe). Keep the `{request_id, zone, event, timestamp, clockValid, source, payload{}}` envelope.
- Existing telemetry payload keys `device`, `sensorHealthy`, `wildlifeDetected`, `uptimeMs` must remain. New keys are appended inside `payload`.
- Never commit `esp32/secrets.h` (git-ignored). Update `secrets.example.h` only.
- Host tests are the gate: `pio test -e native` must pass. Firmware build gate: `pio run -e esp32dev`.
- Device is a **sensor node + local actuator**, never a control plane; it must not publish train state.
- All commits on `master`.

---

## File Structure

- `esp32/src/sensors.h` — pure sensor fusion (PIR + ultrasonic distance + vibration → `animal_detected`).
- `esp32/src/actuator.h` — pure `ActuatorState` (barrier angle, OLED line, buzzer) from `Output` + backend state.
- `esp32/src/telemetry.h` — extended with `distanceM`, `motion`, `vibration`.
- `esp32/railway_controller.ino` — read sensors, drive servo + OLED, publish extended telemetry.
- `esp32/diagram.json` — add HC-SR04, PIR, vibration potentiometer, servo, SSD1306.
- `esp32/libraries.txt` — add Wokwi library names.
- `esp32/test/test_logic/test_logic.cpp` — new Unity cases.
- `docs/wokwi-connectivity.md` — how Wokwi reaches a broker.

---

### Task 1: Pure sensor fusion

**Files:**
- Create: `esp32/src/sensors.h`
- Modify: `esp32/test/test_logic/test_logic.cpp`

**Interfaces:**
- Consumes: nothing.
- Produces: `bool animal_detected(bool pir, int distance_cm, int vibration, int distance_threshold_cm, int vibration_threshold)`.

- [ ] **Step 1: Write the failing test**

Append to `esp32/test/test_logic/test_logic.cpp`:

```cpp
#include "sensors.h"

void test_animal_detected_any_channel() {
  TEST_ASSERT_TRUE(animal_detected(true, 400, 0, 100, 500));    // PIR alone
  TEST_ASSERT_TRUE(animal_detected(false, 60, 0, 100, 500));    // ultrasonic near
  TEST_ASSERT_TRUE(animal_detected(false, 400, 800, 100, 500)); // vibration high
  TEST_ASSERT_FALSE(animal_detected(false, 400, 100, 100, 500)); // all quiet
  TEST_ASSERT_FALSE(animal_detected(false, -1, 0, 100, 500));   // invalid distance ignored
}

int main(int argc, char **argv) {
  UNITY_BEGIN();
  test_animal_detected_any_channel();
  return UNITY_END();
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `pio test -e native` (in `esp32/`)
Expected: compile error `sensors.h: No such file or directory`.

- [ ] **Step 3: Write the header**

`esp32/src/sensors.h`:

```cpp
#pragma once

// Pure fusion of the three wildlife channels. `distance_cm < 0` means the
// ultrasonic reading was invalid/out of range and is ignored.
inline bool animal_detected(bool pir, int distance_cm, int vibration,
                            int distance_threshold_cm, int vibration_threshold) {
  if (pir) return true;
  if (distance_cm >= 0 && distance_cm <= distance_threshold_cm) return true;
  if (vibration >= vibration_threshold) return true;
  return false;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `pio test -e native`
Expected: `OK` (all tests pass).

- [ ] **Step 5: Commit**

```bash
git add esp32/src/sensors.h esp32/test/test_logic/test_logic.cpp
git commit -m "feat(esp32): pure multi-sensor wildlife fusion (PIR + ultrasonic + vibration)"
```

---

### Task 2: Pure actuator derivation (servo barrier + OLED)

**Files:**
- Create: `esp32/src/actuator.h`
- Modify: `esp32/test/test_logic/test_logic.cpp`

**Interfaces:**
- Consumes: `Output` from `output_logic.h`.
- Produces:
  - `int barrier_angle(bool restrictive) -> int` (90 = down/blocking, 0 = up/clear).
  - `const char *status_line(bool local_wildlife, bool local_fault, bool comm_ok, bool backend_restrictive)`.

- [ ] **Step 1: Write the failing test**

Append to `esp32/test/test_logic/test_logic.cpp`:

```cpp
#include "actuator.h"

void test_barrier_and_status() {
  TEST_ASSERT_EQUAL_INT(90, barrier_angle(true));
  TEST_ASSERT_EQUAL_INT(0, barrier_angle(false));
  TEST_ASSERT_EQUAL_STRING("LOCAL WILDLIFE", status_line(true, false, true, false));
  TEST_ASSERT_EQUAL_STRING("SENSOR FAULT", status_line(false, true, true, false));
  TEST_ASSERT_EQUAL_STRING("COMM LOSS", status_line(false, false, false, false));
  TEST_ASSERT_EQUAL_STRING("WILDLIFE", status_line(false, false, true, true));
  TEST_ASSERT_EQUAL_STRING("CLEAR", status_line(false, false, true, false));
}
```

(Add the calls into `main()` under `UNITY_BEGIN()`.)

- [ ] **Step 2: Run to verify it fails** — Run: `pio test -e native` → missing `actuator.h`.

- [ ] **Step 3: Write the header**

`esp32/src/actuator.h`:

```cpp
#pragma once

#include "output_logic.h"

inline int barrier_angle(bool restrictive) { return restrictive ? 90 : 0; }

inline const char *status_line(bool local_wildlife, bool local_fault,
                               bool comm_ok, bool backend_restrictive) {
  if (local_wildlife) return "LOCAL WILDLIFE";
  if (local_fault) return "SENSOR FAULT";
  if (!comm_ok) return "COMM LOSS";
  if (backend_restrictive) return "WILDLIFE";
  return "CLEAR";
}
```

- [ ] **Step 4: Run to verify it passes** — `pio test -e native` → OK.

- [ ] **Step 5: Commit**

```bash
git add esp32/src/actuator.h esp32/test/test_logic/test_logic.cpp
git commit -m "feat(esp32): pure barrier-angle + OLED status derivation"
```

---

### Task 3: Extend telemetry payload with the new sensor fields

**Files:**
- Modify: `esp32/src/telemetry.h`
- Modify: `esp32/test/test_logic/test_logic.cpp`

**Interfaces:**
- Consumes: existing `build_telemetry(...)`.
- Produces: `build_telemetry(... , int distance_m, bool motion, int vibration)` — new trailing params; existing callers keep working via defaults.

- [ ] **Step 1: Write the failing test** — call `build_telemetry(...)` with `distance_m=42, motion=true, vibration=700` and assert the returned string contains `"distanceM":42`, `"motion":true`, `"vibration":700`.

- [ ] **Step 2: Run to verify it fails** — `pio test -e native` → no matching overload.

- [ ] **Step 3: Extend the function** — append `,\"distanceM\":%d,\"motion\":%s,\"vibration\":%d` inside the `payload` object, with defaults `int distance_m = -1, bool motion = false, int vibration = 0` on the new params.

- [ ] **Step 4: Run to verify it passes** — `pio test -e native` → OK.

- [ ] **Step 5: Commit**

```bash
git add esp32/src/telemetry.h esp32/test/test_logic/test_logic.cpp
git commit -m "feat(esp32): telemetry payload carries distance/motion/vibration"
```

---

### Task 4: Firmware glue — sensors, servo, OLED

**Files:**
- Modify: `esp32/railway_controller.ino`
- Modify: `esp32/secrets.example.h` (add device threshold/pin docs only)

**Interfaces:**
- Consumes: `animal_detected`, `barrier_angle`, `status_line`, the existing `decide_output`/`applyOutputs`.
- Produces: an extended `applyOutputs()` that also drives the servo and OLED; a `readSensors()` returning `{pir, distance_cm, vibration}`.

- [ ] **Step 1: Add the pins + devices**

```cpp
#include <ESP32Servo.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "src/sensors.h"
#include "src/actuator.h"

const int TRIG_PIN = 5, ECHO_PIN = 18;   // HC-SR04
const int PIR_PIN = 19;                  // PIR
const int VIBRATION_PIN = 34;            // analog
const int SERVO_PIN = 13;
const int DISTANCE_THRESHOLD_CM = 100;
const int VIBRATION_THRESHOLD = 800;

Servo barrier;
Adafruit_SSD1306 oled(128, 64, &Wire, -1);
```

- [ ] **Step 2: Read sensors**

```cpp
int readDistanceCm() {
  digitalWrite(TRIG_PIN, LOW); delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH); delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  const unsigned long us = pulseIn(ECHO_PIN, HIGH, 30000);
  const int cm = us == 0 ? -1 : static_cast<int>(us / 58);
  return (cm < 0 || cm > 400) ? -1 : cm;
}
```

- [ ] **Step 3: Drive the actuators**

```cpp
void applyOutputs() {
  const bool backendRestrictive = backendWildlifeDetected || backendFaultDetected;
  const Output output = decide_output(localWildlifeDetected, localFaultDetected,
                                      mqtt.connected() && backendContextFresh, backendRestrictive);
  const bool restrictive = output != Output::RENDER_BACKEND || backendRestrictive;
  digitalWrite(RED_LED, restrictive ? HIGH : LOW);
  digitalWrite(GREEN_LED, restrictive ? LOW : HIGH);
  digitalWrite(BUZZER, output == Output::COMM_LOSS ? ((millis() / 250) % 2) : (restrictive ? HIGH : LOW));
  barrier.write(barrier_angle(restrictive));
  oled.clearDisplay();
  oled.setCursor(0, 0);
  oled.println(status_line(localWildlifeDetected, localFaultDetected,
                           mqtt.connected() && backendContextFresh, backendRestrictive));
  oled.display();
}
```

- [ ] **Step 4: Fuse the sensors in `loop()`** — set `localWildlifeDetected = wildlifeDebouncer.update(animal_detected(pir, readDistanceCm(), analogRead(VIBRATION_PIN), DISTANCE_THRESHOLD_CM, VIBRATION_THRESHOLD), millis());` and include `distance_m/motion/vibration` when building telemetry.

- [ ] **Step 5: Build**

Run: `pio run -e esp32dev` (in `esp32/`)
Expected: `SUCCESS`.

- [ ] **Step 6: Commit**

```bash
git add esp32/railway_controller.ino esp32/secrets.example.h
git commit -m "feat(esp32): drive servo barrier + OLED; fuse ultrasonic/PIR/vibration"
```

---

### Task 5: Wokwi diagram + libraries

**Files:**
- Modify: `esp32/diagram.json`
- Modify: `esp32/libraries.txt`

**Interfaces:**
- Consumes: pin assignments from Task 4.
- Produces: a Wokwi circuit with the new parts wired.

- [ ] **Step 1: Add the parts to `diagram.json`** — append to `parts`:

```json
{ "type": "wokwi-hc-sr04", "id": "us", "top": -160, "left": 260, "attrs": {} },
{ "type": "wokwi-pir-motion-sensor", "id": "pir", "top": -160, "left": 420, "attrs": {} },
{ "type": "wokwi-potentiometer", "id": "vib", "top": -60, "left": 420, "attrs": { "value": "0" } },
{ "type": "wokwi-servo", "id": "servo", "top": 90, "left": 420, "attrs": { "horn": "white" } },
{ "type": "board-ssd1306", "id": "oled", "top": 240, "left": 260, "attrs": { "i2cAddress": "0x3c" } }
```

- [ ] **Step 2: Wire connections** — add to `connections`:

```json
[ "esp:5", "us:TRIG", "green", [] ], [ "esp:18", "us:ECHO", "green", [] ],
[ "esp:3V3", "us:VCC", "red", [] ], [ "us:GND", "esp:GND.1", "black", [] ],
[ "esp:3V3", "pir:VCC", "red", [] ], [ "pir:OUT", "esp:19", "green", [] ], [ "pir:GND", "esp:GND.1", "black", [] ],
[ "esp:3V3", "vib:VCC", "red", [] ], [ "vib:SIG", "esp:34", "green", [] ], [ "vib:GND", "esp:GND.1", "black", [] ],
[ "esp:13", "servo:PWM", "orange", [] ], [ "esp:3V3", "servo:V+", "red", [] ], [ "servo:GND", "esp:GND.1", "black", [] ],
[ "esp:21", "oled:SDA", "blue", [] ], [ "esp:22", "oled:SCL", "yellow", [] ], [ "esp:3V3", "oled:VCC", "red", [] ], [ "oled:GND", "esp:GND.1", "black", [] ]
```

- [ ] **Step 3: Libraries** — set `esp32/libraries.txt` to:

```
PubSubClient
ArduinoJson
ESP32Servo
Adafruit SSD1306
Adafruit GFX Library
```

- [ ] **Step 4: Verify JSON + document pins** — `python -c "import json;json.load(open('esp32/diagram.json'))"` → no error.

- [ ] **Step 5: Commit**

```bash
git add esp32/diagram.json esp32/libraries.txt
git commit -m "feat(esp32): Wokwi diagram adds ultrasonic/PIR/vibration/servo/OLED"
```

---

### Task 6: Wokwi → broker connectivity doc

**Files:**
- Create: `docs/wokwi-connectivity.md`

**Interfaces:**
- Consumes: nothing.
- Produces: setup instructions for reaching a broker from Wokwi.

- [ ] **Step 1: Write the doc** — cover: Wokwi uses `Wokwi-GUEST` WiFi and can only reach internet-reachable hosts; a local Mosquitto needs a tunnel (`cloudflared tunnel --url tcp://localhost:1883` or `ngrok tcp 1883`); set `MQTT_HOST` to the tunnel host, never `localhost`; dev creds and topic list; test by watching `railway/telemetry/esp32` with `mosquitto_sub`.
- [ ] **Step 2: Commit** — `git add docs/wokwi-connectivity.md && git commit -m "docs: Wokwi-to-broker connectivity setup"`.

---

## Self-Review

- **Spec coverage:** §11 sensors → Tasks 1, 4; LEDs/buzzer → existing + Task 4; servo barrier → Tasks 2, 4; OLED → Tasks 2, 4; WiFi/MQTT → existing + Task 6; telemetry fields → Task 3. §15 host tests → every task's `pio test -e native`.
- **Placeholder scan:** none; all headers and tests show code.
- **Type consistency:** `animal_detected` (Task 1) used in Task 4; `barrier_angle`/`status_line` (Task 2) used in Task 4; `build_telemetry` new params (Task 3) used in Task 4.
- **Concurrency:** every task reiterates the additive/coordinate rule; `output_logic`/`command_logic` untouched.
