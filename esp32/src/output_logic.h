#pragma once

// Demo-output policy. Local observations always dominate remote state.
enum class Output { RESTRICTIVE, COMM_LOSS, RENDER_BACKEND, WARNING };

inline Output decide_output(bool local_wildlife, bool local_fault,
                            bool comm_ok, bool backend_restrictive,
                            bool backend_near = false) {
  (void)backend_restrictive;  // Used by the caller when rendering backend state.
  if (local_wildlife || local_fault) return Output::RESTRICTIVE;
  if (!comm_ok) return Output::COMM_LOSS;
  if (backend_restrictive) return Output::RENDER_BACKEND;
  if (backend_near) return Output::WARNING;
  return Output::RENDER_BACKEND;
}
