#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
declare -A RESULTS=()

run_check() {
  local name="$1"
  shift
  if "$@"; then
    RESULTS["$name"]="PASS"
  else
    RESULTS["$name"]="FAIL"
  fi
}

if [[ -f "$ROOT/backend/package.json" ]]; then
  run_check backend bash -c "cd '$ROOT' && npm --prefix backend test"
else
  RESULTS[backend]="NOT_RUN"
fi

if [[ -f "$ROOT/web/package.json" ]]; then
  run_check web_build bash -c "cd '$ROOT/web' && npm run build"
else
  RESULTS[web_build]="NOT_RUN"
fi

if [[ -f "$ROOT/scripts/test-backend.sh" ]]; then
  run_check acl bash "$ROOT/scripts/test-backend.sh"
else
  RESULTS[acl]="NOT_RUN"
fi

if [[ -f "$ROOT/godot/project.godot" ]]; then
  if [[ -x "$HOME/apps/godot/Godot_v4.7.2-stable_linux.x86_64" ]]; then
    run_check godot_headless bash -c "'$HOME/apps/godot/Godot_v4.7.2-stable_linux.x86_64' --headless --editor --path '$ROOT/godot' --quit"
  else
    RESULTS[godot_headless]="NOT_RUN"
  fi
else
  RESULTS[godot_headless]="NOT_RUN"
fi

if [[ -f "$ROOT/esp32/platformio.ini" ]]; then
  if command -v pio >/dev/null 2>&1; then
    run_check esp32_compile bash -c "cd '$ROOT/esp32' && pio run"
  else
    RESULTS[esp32_compile]="NOT_RUN"
  fi
else
  RESULTS[esp32_compile]="NOT_RUN"
fi

printf '\n=== Gate results ===\n'
for key in backend web_build acl godot_headless esp32_compile; do
  printf '%-18s %s\n' "$key" "${RESULTS[$key]:-NOT_RUN}"
done

failures=0
for key in backend web_build acl godot_headless esp32_compile; do
  if [[ "${RESULTS[$key]:-NOT_RUN}" == "FAIL" ]]; then
    failures=$((failures + 1))
  fi
done

if (( failures > 0 )); then
  exit 1
fi

exit 0
