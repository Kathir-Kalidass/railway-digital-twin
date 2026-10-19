#pragma once

// Demo-output policy. Local observations always dominate remote state.
enum class Output { RESTRICTIVE, COMM_LOSS, RENDER_BACKEND };

inline Output decide_output(bool local_wildlife, bool local_fault,
                            bool comm_ok, bool backend_restrictive) {
  (void)backend_restrictive;  // Used by the caller when rendering backend state.
  if (local_wildlife || local_fault) return Output::RESTRICTIVE;
  if (!comm_ok) return Output::COMM_LOSS;
  return Output::RENDER_BACKEND;
}
