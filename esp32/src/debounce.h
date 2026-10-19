#pragma once

static const unsigned long DEBOUNCE_MS = 40;

struct Debouncer {
  bool stable = false;
  bool last_raw = false;
  unsigned long last_change = 0;

  bool update(bool raw, unsigned long now_ms) {
    if (raw != last_raw) {
      last_raw = raw;
      last_change = now_ms;
      return stable;
    }
    if (raw != stable && (now_ms - last_change) >= DEBOUNCE_MS) stable = raw;
    return stable;
  }
};
