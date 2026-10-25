#pragma once

#include <cstdio>
#include <string>

// Telemetry/command request id, unique across device reboots: the sequence
// counter restarts at boot, so the id must also carry a per-boot nonce
// (hardware RNG or the epoch-sourced wall clock) to avoid colliding with the
// ids the backend already remembers from a previous device session.
inline std::string build_request_id(const char *device, unsigned long long mac,
                                    unsigned long long boot_nonce, unsigned long seq) {
  char buffer[80];
  std::snprintf(buffer, sizeof(buffer), "%s-%llx-%llu-%lu", device, mac, boot_nonce, seq);
  return std::string(buffer);
}

inline std::string telemetry_json_escape(const char *value) {
  std::string escaped;
  for (const unsigned char *p = reinterpret_cast<const unsigned char *>(value ? value : ""); *p; ++p) {
    switch (*p) {
      case '\\': escaped += "\\\\"; break;
      case '"': escaped += "\\\""; break;
      case '\n': escaped += "\\n"; break;
      case '\r': escaped += "\\r"; break;
      case '\t': escaped += "\\t"; break;
      default:
        if (*p < 0x20) {
          char encoded[7];
          std::snprintf(encoded, sizeof(encoded), "\\u%04x", *p);
          escaped += encoded;
        } else {
          escaped += static_cast<char>(*p);
        }
    }
  }
  return escaped;
}

inline std::string build_telemetry(const char *device, const char *zone,
                                   const char *request_id, const char *iso_timestamp,
                                   bool clock_valid, bool wildlife,
                                   bool sensor_healthy, unsigned long uptime_ms,
                                   float distance_m = -1.0f, bool motion = false, int vibration = 0,
                                   bool near_animal = false) {
  const std::string timestamp = clock_valid
    ? "\"" + telemetry_json_escape(iso_timestamp) + "\""
    : "null";
  char tail[256];
  std::snprintf(tail, sizeof(tail),
                ",\"clockValid\":%s,\"source\":\"esp32\",\"payload\":{"
                "\"device\":\"%s\",\"sensorHealthy\":%s,\"wildlifeDetected\":%s,"
                "\"nearAnimal\":%s,\"uptimeMs\":%lu,\"distanceM\":%g,"
                "\"motion\":%s,\"vibration\":%d}}",
                clock_valid ? "true" : "false", telemetry_json_escape(device).c_str(),
                sensor_healthy ? "true" : "false", wildlife ? "true" : "false",
                near_animal ? "true" : "false", uptime_ms,
                distance_m, motion ? "true" : "false", vibration);
  return "{\"request_id\":\"" + telemetry_json_escape(request_id) +
         "\",\"zone\":\"" + telemetry_json_escape(zone) +
         "\",\"event\":\"DEVICE_TELEMETRY\",\"timestamp\":" + timestamp + tail;
}
