#pragma once

// Copy this file to secrets.h (which is intentionally git-ignored) and fill
// in values reachable by the ESP32/Wokwi device. Never commit real secrets.
#define WIFI_SSID "Wokwi-GUEST"
#define WIFI_PASSWORD ""
#define MQTT_HOST "192.168.1.10"  // Device-reachable broker; never localhost.
#define MQTT_PORT 1883
#define MQTT_USER "esp32"
#define MQTT_PASS "change-me"
#define DEVICE_ID "esp32"
#define DEVICE_ZONE "zone1"

// Stage D sensor/actuator wiring defaults (override in secrets.h if needed).
// TRIG=5 ECHO=18 (HC-SR04), PIR=19, vibration analog=34, servo=13,
// OLED SSD1306 I2C SDA=21 SCL=22 at address 0x3C.
// Distance threshold 100 cm, vibration threshold 800 (0-4095).
