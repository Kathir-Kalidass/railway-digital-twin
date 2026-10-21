/*
  Railway Digital Twin - ESP32 MQTT controller demo
  Educational simulation only; not for real railway signalling.
  Libraries: PubSubClient by Nick O'Leary.
*/
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <time.h>
#include "secrets.h"
#include "command_logic.h"
#include "debounce.h"
#include "output_logic.h"
#include "telemetry.h"
#include "sensors.h"
#include "actuator.h"

const char* TOPIC_COMMANDS = "railway/commands/esp32";
const char* TOPIC_TELEMETRY = "railway/telemetry/esp32";

// Demo GPIOs: LEDs can represent restrictive/normal signal and a buzzer.
const int RED_LED = 25;
const int GREEN_LED = 26;
const int BUZZER = 27;
const int WILDLIFE_INPUT = 33; // Optional active-high pushbutton/sensor simulation
const int FAULT_INPUT = 32;    // Optional active-high pushbutton/sensor fault simulation

// Stage D sensor/actuator pins (Wokwi-compatible defaults).
const int TRIG_PIN = 5;
const int ECHO_PIN = 18;
const int PIR_PIN = 19;
const int VIBRATION_PIN = 34;
const int SERVO_PIN = 13;
const int DISTANCE_THRESHOLD_CM = 100;
const int VIBRATION_THRESHOLD = 800;
const unsigned long SENSOR_SAMPLE_MS = 100;

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
Servo barrier;
Adafruit_SSD1306 oled(128, 64, &Wire, -1);
bool localWildlifeDetected = false;
bool localFaultDetected = false;
bool backendWildlifeDetected = false;
bool backendFaultDetected = false;
bool backendContextFresh = false;
bool localPirDetected = false;
int localDistanceCm = -1;
int localVibration = 0;
unsigned long lastSensorSample = 0;
unsigned long lastPublish = 0;
unsigned long telemetrySequence = 0;
unsigned long nextWiFiAttempt = 0;
unsigned long nextMqttAttempt = 0;
unsigned long wifiBackoff = 1000;
unsigned long mqttBackoff = 1000;
String acceptedCommandIds[8];
uint8_t acceptedCommandIndex = 0;
Debouncer wildlifeDebouncer;
Debouncer faultDebouncer;

const unsigned long HEARTBEAT_MS = 1500;
const unsigned long RETRY_MAX_MS = 30000;

void applyOutputs() {
  const bool backendRestrictive = backendWildlifeDetected || backendFaultDetected;
  const bool commOk = mqtt.connected() && backendContextFresh;
  const Output output = decide_output(localWildlifeDetected, localFaultDetected, commOk, backendRestrictive);
  const bool restrictive = output != Output::RENDER_BACKEND || backendRestrictive;
  digitalWrite(RED_LED, restrictive ? HIGH : LOW);
  digitalWrite(GREEN_LED, restrictive ? LOW : HIGH);
  // Communication loss remains restrictive but is distinguishable by a pulse.
  digitalWrite(BUZZER, output == Output::COMM_LOSS ? ((millis() / 250) % 2) : (restrictive ? HIGH : LOW));
  barrier.write(barrier_angle(restrictive));
  oled.clearDisplay();
  oled.setCursor(0, 0);
  oled.println(status_line(localWildlifeDetected, localFaultDetected, commOk, backendRestrictive));
  oled.setCursor(0, 16);
  char sensorLines[64];
  snprintf(sensorLines, sizeof(sensorLines), "Dist: %d cm\nVib:  %d\nWiFi: %s\n",
           localDistanceCm, localVibration, WiFi.status() == WL_CONNECTED ? "up" : "down");
  oled.print(sensorLines);
  oled.display();
}

int readDistanceCm() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  const unsigned long us = pulseIn(ECHO_PIN, HIGH, 30000);
  if (us == 0) return -1;
  const int cm = static_cast<int>(us / 58);
  return (cm < 0 || cm > 400) ? -1 : cm;
}

bool commandAlreadyAccepted(const char *requestId) {
  for (const String &accepted : acceptedCommandIds) {
    if (accepted == requestId) return true;
  }
  return false;
}

void rememberCommand(const char *requestId) {
  acceptedCommandIds[acceptedCommandIndex] = requestId;
  acceptedCommandIndex = (acceptedCommandIndex + 1) % 8;
}

bool commandTimestampFresh(const char *timestamp) {
  if (!timestamp || !timestamp[0]) return false;
  int year, month, day, hour, minute, second;
  if (sscanf(timestamp, "%d-%d-%dT%d:%d:%d", &year, &month, &day, &hour, &minute, &second) != 6) return false;
  struct tm parsed = {};
  parsed.tm_year = year - 1900; parsed.tm_mon = month - 1; parsed.tm_mday = day;
  parsed.tm_hour = hour; parsed.tm_min = minute; parsed.tm_sec = second;
  const time_t commandTime = mktime(&parsed);
  const time_t currentTime = time(nullptr);
  return currentTime > 1600000000 && commandTime > 1600000000 &&
         llabs(static_cast<long long>(currentTime) - static_cast<long long>(commandTime)) <= 5 * 60;
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  if (String(topic) != TOPIC_COMMANDS) return;
  StaticJsonDocument<512> document;
  if (deserializeJson(document, payload, length)) return;
  const char *zone = document["zone"] | "";
  const char *requestId = document["request_id"] | "";
  const char *timestamp = document["timestamp"] | "";
  const char *source = document["source"] | "";
  if (strcmp(zone, DEVICE_ZONE) != 0 || strcmp(source, "dashboard") != 0 || !requestId[0] ||
      !document["payload"].is<JsonObject>() || !commandTimestampFresh(timestamp) ||
      commandAlreadyAccepted(requestId)) return;
  std::string message(reinterpret_cast<const char *>(payload), length);
  const CmdEffect effect = parse_command(message, DEVICE_ZONE, millis());
  if (effect == CmdEffect::NONE) return;
  rememberCommand(requestId);
  backendContextFresh = true;
  if (effect == CmdEffect::WILDLIFE_SET) backendWildlifeDetected = true;
  else if (effect == CmdEffect::WILDLIFE_CLEAR) backendWildlifeDetected = false;
  else if (effect == CmdEffect::FAULT_SET) backendFaultDetected = true;
  else if (effect == CmdEffect::FAULT_RESTORE) backendFaultDetected = false;
  else if (effect == CmdEffect::RESET && !localWildlifeDetected && !localFaultDetected) {
    backendWildlifeDetected = false;
    backendFaultDetected = false;
  }
  applyOutputs();
}

void setup() {
  Serial.begin(115200);
  pinMode(RED_LED, OUTPUT); pinMode(GREEN_LED, OUTPUT); pinMode(BUZZER, OUTPUT);
  pinMode(WILDLIFE_INPUT, INPUT_PULLDOWN); pinMode(FAULT_INPUT, INPUT_PULLDOWN);
  pinMode(TRIG_PIN, OUTPUT); pinMode(ECHO_PIN, INPUT);
  pinMode(PIR_PIN, INPUT); pinMode(VIBRATION_PIN, INPUT);
  Wire.begin(21, 22);
  barrier.attach(SERVO_PIN);
  if (!oled.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("OLED init failed");
  }
  oled.clearDisplay();
  oled.setTextSize(1);
  oled.setTextColor(SSD1306_WHITE);
  // mqtt is disconnected at boot, so this is a restrictive indication.
  applyOutputs();
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(onMqttMessage);
  mqtt.setBufferSize(512);
}

void publishTelemetry() {
  const time_t now = time(nullptr);
  const bool clockValid = now > 1600000000;
  char timestamp[25] = "";
  if (clockValid) {
    struct tm utc;
    gmtime_r(&now, &utc);
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", &utc);
  }
  char requestId[80];
  snprintf(requestId, sizeof(requestId), "%s-%llx-%lu", DEVICE_ID,
           ESP.getEfuseMac(), ++telemetrySequence);
  const std::string payload = build_telemetry(DEVICE_ID, DEVICE_ZONE, requestId, timestamp,
                                              clockValid, localWildlifeDetected, !localFaultDetected,
                                              millis(), distance_cm_to_m(localDistanceCm),
                                              localPirDetected, localVibration);
  mqtt.publish(TOPIC_TELEMETRY, payload.c_str(), false);
}

void sampleInputs(unsigned long now) {
  if (now - lastSensorSample >= SENSOR_SAMPLE_MS) {
    lastSensorSample = now;
    localDistanceCm = readDistanceCm();
    localPirDetected = digitalRead(PIR_PIN) == HIGH;
    localVibration = analogRead(VIBRATION_PIN);
  }
  const bool fusedWildlife =
      animal_detected(localPirDetected, localDistanceCm, localVibration,
                      DISTANCE_THRESHOLD_CM, VIBRATION_THRESHOLD) ||
      digitalRead(WILDLIFE_INPUT) == HIGH;
  const bool wildlife = wildlifeDebouncer.update(fusedWildlife, now);
  const bool fault = faultDebouncer.update(digitalRead(FAULT_INPUT) == HIGH, now);
  if (wildlife != localWildlifeDetected || fault != localFaultDetected) {
    localWildlifeDetected = wildlife;
    localFaultDetected = fault;
    applyOutputs();
    if (mqtt.connected()) {
      publishTelemetry();  // stable input changes are reported immediately; nothing is queued.
      lastPublish = now;
    }
  }
}

void attemptWiFi(unsigned long now) {
  if (WiFi.status() == WL_CONNECTED) {
    wifiBackoff = 1000;
    return;
  }
  if (now < nextWiFiAttempt) return;
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  nextWiFiAttempt = now + wifiBackoff;
  wifiBackoff = min(wifiBackoff * 2, RETRY_MAX_MS);
}

void attemptMqtt(unsigned long now) {
  if (WiFi.status() != WL_CONNECTED || mqtt.connected()) return;
  if (now < nextMqttAttempt) return;
  const String clientId = String("railway-") + DEVICE_ID + "-" + String((uint32_t)ESP.getEfuseMac(), HEX);
  if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS)) {
    mqttBackoff = 1000;
    mqtt.subscribe(TOPIC_COMMANDS);
    // Keep the output restrictive until a new valid command establishes context.
    backendContextFresh = false;
    publishTelemetry();
    lastPublish = now;
  } else {
    nextMqttAttempt = now + mqttBackoff;
    mqttBackoff = min(mqttBackoff * 2, RETRY_MAX_MS);
  }
}

void loop() {
  const unsigned long now = millis();
  sampleInputs(now);
  attemptWiFi(now);
  attemptMqtt(now);

  if (mqtt.connected()) {
    mqtt.loop();
    if (now - lastPublish >= HEARTBEAT_MS) {
      lastPublish = now;
      publishTelemetry();
    }
  } else {
    // A disconnect is never a false clear: preserve local state and require
    // a new backend context after reconnect.
    backendContextFresh = false;
  }
  applyOutputs();
}
