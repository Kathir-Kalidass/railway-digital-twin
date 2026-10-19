/*
  Railway Digital Twin - ESP32 MQTT controller demo
  Educational simulation only; not for real railway signalling.
  Libraries: PubSubClient by Nick O'Leary.
*/
#include <WiFi.h>
#include <PubSubClient.h>
#include <time.h>
#include "secrets.h"
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
bool wildlifeDetected = false;
bool sensorHealthy = true;
unsigned long lastPublish = 0;
unsigned long telemetrySequence = 0;

void applyOutputs() {
  const bool restrictive = wildlifeDetected || !sensorHealthy;
  digitalWrite(RED_LED, restrictive ? HIGH : LOW);
  digitalWrite(GREEN_LED, restrictive ? LOW : HIGH);
  digitalWrite(BUZZER, restrictive ? HIGH : LOW);
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  if (String(topic) != TOPIC_COMMANDS) return;
  String message;
  for (unsigned int i = 0; i < length; i++) message += (char)payload[i];
  if (message.indexOf("WILDLIFE_DETECTED") >= 0) wildlifeDetected = true;
  else if (message.indexOf("WILDLIFE_CLEARED") >= 0) wildlifeDetected = false;
  else if (message.indexOf("SENSOR_FAULT") >= 0) sensorHealthy = false;
  else if (message.indexOf("SENSOR_RESTORED") >= 0) sensorHealthy = true;
  else if (message.indexOf("RESET") >= 0 && !wildlifeDetected && sensorHealthy) {
    // Reset does not override an active hazard/fault.
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
                                              clockValid, wildlifeDetected, sensorHealthy,
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
  if (nowWildlife != lastWildlife) { wildlifeDetected = nowWildlife; lastWildlife = nowWildlife; applyOutputs(); }
  if (nowFault != lastFault) { sensorHealthy = !nowFault; lastFault = nowFault; applyOutputs(); }

  if (millis() - lastPublish > 1500) {
    lastPublish = millis();
    publishTelemetry();
  }
  delay(10);
}
