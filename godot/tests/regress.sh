#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
status=0

echo "== backend (starts Mosquitto and runs node --test) =="
bash "$ROOT/scripts/test-backend.sh" || status=1

echo "== godot headless =="
bash "$ROOT/godot/tests/run_tests.sh" || status=1

echo "== esp32 host tests =="
( cd "$ROOT/esp32" && pio test -e native ) || status=1

echo "== esp32 firmware build =="
( cd "$ROOT/esp32" && pio run -e esp32dev ) || status=1

echo
if [ "$status" -eq 0 ]; then
  echo "REGRESSION: PASS"
else
  echo "REGRESSION: FAIL"
fi
exit "$status"
