#pragma once

#include "output_logic.h"

inline int barrier_angle(bool restrictive) { return restrictive ? 90 : 0; }

inline const char *status_line(bool local_wildlife, bool local_fault,
                               bool comm_ok, bool backend_restrictive,
                               bool backend_near = false) {
  if (local_wildlife) return "LOCAL WILDLIFE";
  if (local_fault) return "SENSOR FAULT";
  if (!comm_ok) return "COMM LOSS";
  if (backend_restrictive) return "WILDLIFE";
  if (backend_near) return "ANIMAL NEAR";
  return "CLEAR";
}
