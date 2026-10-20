#pragma once

#include <cstdio>
#include <string>

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
                                   float distance_m = -1.0f, bool motion = false, int vibration = 0) {
  const std::string timestamp = clock_valid
    ? "\"" + telemetry_json_escape(iso_timestamp) + "\""
    : "null";
  char tail[256];
  std::snprintf(tail, sizeof(tail),
                ",\"clockValid\":%s,\"source\":\"esp32\",\"payload\":{"
                "\"device\":\"%s\",\"sensorHealthy\":%s,\"wildlifeDetected\":%s,"
                "\"uptimeMs\":%lu,\"distanceM\":%g,\"motion\":%s,\"vibration\":%d}}",
                clock_valid ? "true" : "false", telemetry_json_escape(device).c_str(),
                sensor_healthy ? "true" : "false", wildlife ? "true" : "false", uptime_ms,
                distance_m, motion ? "true" : "false", vibration);
  return "{\"request_id\":\"" + telemetry_json_escape(request_id) +
         "\",\"zone\":\"" + telemetry_json_escape(zone) +
         "\",\"event\":\"DEVICE_TELEMETRY\",\"timestamp\":" + timestamp + tail;
}
