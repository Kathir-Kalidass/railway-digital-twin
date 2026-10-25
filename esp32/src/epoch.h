// Wall-clock bootstrap for devices whose network cannot reach SNTP (gated
// networks, the Wokwi Private IoT Gateway). The backend publishes its own
// epoch on railway/boot (retained); the device derives a wall clock from it:

#pragma once

#include <cstdint>

struct EpochSource {
  bool calibrated = false;
  unsigned long long epochBaseMs = 0;
  unsigned long long seenAtMs = 0;

  void update(unsigned long long epochMs, unsigned long long nowMs) {
    if (epochMs < 1600000000000ULL) return;
    epochBaseMs = epochMs;
    seenAtMs = nowMs;
    calibrated = true;
  }

  long long nowMs(unsigned long long ms) const {
    if (!calibrated) return 0;
    return static_cast<long long>(epochBaseMs + ms) - static_cast<long long>(seenAtMs);
  }

  bool validNow(unsigned long long ms) const {
    return nowMs(ms) > 1600000000000LL;
  }
};
