#pragma once

#include <cctype>
#include <string>

enum class CmdEffect { NONE, WILDLIFE_SET, WILDLIFE_CLEAR, FAULT_SET, FAULT_RESTORE, RESET };

// This small parser intentionally accepts only a JSON object with exact string
// fields. The sketch performs full ArduinoJson envelope/freshness/dedup checks
// before calling this pure mapper; keeping this header dependency-free lets the
// host tests run without Arduino libraries.
inline bool command_json_string(const std::string &json, const char *key, std::string *value) {
  const std::string needle = std::string("\"") + key + "\"";
  const size_t key_at = json.find(needle);
  if (key_at == std::string::npos) return false;
  size_t at = key_at + needle.size();
  while (at < json.size() && std::isspace(static_cast<unsigned char>(json[at]))) ++at;
  if (at == json.size() || json[at++] != ':') return false;
  while (at < json.size() && std::isspace(static_cast<unsigned char>(json[at]))) ++at;
  if (at == json.size() || json[at++] != '\"') return false;
  const size_t start = at;
  bool escaped = false;
  for (; at < json.size(); ++at) {
    if (escaped) { escaped = false; continue; }
    if (json[at] == '\\') { escaped = true; continue; }
    if (json[at] == '\"') {
      if (value) *value = json.substr(start, at - start);
      return true;
    }
  }
  return false;
}

inline CmdEffect parse_command(const std::string &json, const char *expected_zone,
                               unsigned long now_ms) {
  (void)now_ms;
  const size_t begin = json.find_first_not_of(" \t\r\n");
  const size_t end = json.find_last_not_of(" \t\r\n");
  if (begin == std::string::npos || json[begin] != '{' || json[end] != '}') return CmdEffect::NONE;
  std::string zone;
  std::string event;
  if (!command_json_string(json, "zone", &zone) || zone != expected_zone ||
      !command_json_string(json, "event", &event)) return CmdEffect::NONE;
  if (event == "WILDLIFE_DETECTED") return CmdEffect::WILDLIFE_SET;
  if (event == "WILDLIFE_CLEARED") return CmdEffect::WILDLIFE_CLEAR;
  if (event == "SENSOR_FAULT") return CmdEffect::FAULT_SET;
  if (event == "SENSOR_RESTORED") return CmdEffect::FAULT_RESTORE;
  if (event == "RESET") return CmdEffect::RESET;
  return CmdEffect::NONE;
}
