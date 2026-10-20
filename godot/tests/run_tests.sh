#!/usr/bin/env bash
set -euo pipefail
GODOT="${GODOT:-/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # -> godot/
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
status=0
for t in "$ROOT"/tests/test_*.gd; do
  base="$(basename "$t")"
  [ "$base" = "test_harness.gd" ] && continue   # helper, not a SceneTree test
  if ! "$GODOT" --headless --path "$ROOT" --script "res://tests/$base"; then
    status=1
  fi
done
exit $status
