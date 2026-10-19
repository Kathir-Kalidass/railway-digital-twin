/*
  Railway Digital Twin - ESP32 MQTT controller demo
  Educational simulation only; not for real railway signalling.
  Libraries: PubSubClient by Nick O'Leary.
*/
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <time.h>
#include "secrets.h"
#include "src/command_logic.h"
#include "src/output_logic.h"
#include "src/telemetry.h"

const char* TOPIC_COMMANDS = "railway/commands/esp32";
const char* TOPIC_TELEMETRY = "railway/telemetry/esp32";

// Demo GPIOs: LEDs can represent restrictive/normal signal and a buzzer.
const int RED_LED = 25;
const int GREEN_LED = 26;
const int BUZZER = 27;
const int WILDLIFE_INPUT = 33; // Optional active-high pushbutton/sensor simulation
const int FAULT_INPUT = 32;    // Optional active-high pushbutton/sensor fault simulation

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
bool localWildlifeDetected = false;
bool localFaultDetected = false;
bool backendWildlifeDetected = false;
bool backendFaultDetected = false;
unsigned long lastPublish = 0;
unsigned long telemetrySequence = 0;
String lastCommandId;

void applyOutputs() {
  const bool backendRestrictive = backendWildlifeDetected || backendFaultDetected;
  const Output output = decide_output(localWildlifeDetected, localFaultDetected,
                                      mqtt.connected(), backendRestrictive);
  const bool restrictive = output != Output::RENDER_BACKEND || backendRestrictive;
  digitalWrite(RED_LED, restrictive ? HIGH : LOW);
  digitalWrite(GREEN_LED, restrictive ? LOW : HIGH);
  // Communication loss remains restrictive but is distinguishable by a pulse.
  digitalWrite(BUZZER, output == Output::COMM_LOSS ? ((millis() / 250) % 2) : (restrictive ? HIGH : LOW));
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
  if (strcmp(zone, DEVICE_ZONE) != 0 || !requestId[0] || !commandTimestampFresh(timestamp) ||
      lastCommandId == requestId) return;
  std::string message(reinterpret_cast<const char *>(payload), length);
  const CmdEffect effect = parse_command(message, DEVICE_ZONE, millis());
  if (effect == CmdEffect::NONE) return;
  lastCommandId = requestId;
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

void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) delay(250);
}

void connectMqtt() {
  while (!mqtt.connected()) {
    String clientId = "railway-esp32-" + String((uint32_t)ESP.getEfuseMac(), HEX);
    if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS)) {
      mqtt.subscribe(TOPIC_COMMANDS);
    } else {
      delay(1500);
    }
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(RED_LED, OUTPUT); pinMode(GREEN_LED, OUTPUT); pinMode(BUZZER, OUTPUT);
  pinMode(WILDLIFE_INPUT, INPUT_PULLDOWN); pinMode(FAULT_INPUT, INPUT_PULLDOWN);
  applyOutputs();
  connectWiFi();
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
                                              millis());
  mqtt.publish(TOPIC_TELEMETRY, payload.c_str(), false);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) connectWiFi();
  if (!mqtt.connected()) connectMqtt();
  mqtt.loop();

  // Optional local input simulation: active-high inputs.
  static bool lastWildlife = false, lastFault = false;
  bool nowWildlife = digitalRead(WILDLIFE_INPUT) == HIGH;
  bool nowFault = digitalRead(FAULT_INPUT) == HIGH;
  if (nowWildlife != lastWildlife) {
    localWildlifeDetected = nowWildlife;
    lastWildlife = nowWildlife;
    applyOutputs();
  }
  if (nowFault != lastFault) {
    localFaultDetected = nowFault;
    lastFault = nowFault;
    applyOutputs();
  }

  if (millis() - lastPublish > 1500) {
    lastPublish = millis();
    publishTelemetry();
  }
  delay(10);
}
