#pragma once

inline bool animal_detected(bool pir, int distance_cm, int vibration,
                            int distance_threshold_cm, int vibration_threshold) {
  if (pir) return true;
  if (distance_cm >= 0 && distance_cm <= distance_threshold_cm) return true;
  if (vibration >= vibration_threshold) return true;
  return false;
}

inline float distance_cm_to_m(int distance_cm) {
  if (distance_cm < 0) return -1.0f;
  return distance_cm / 100.0f;
}
