#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_PORT="${MQTT_LOCAL_PORT:-1883}"
ESP32_PASS="${MQTT_ESP32_PASS:-esp32-dev-pass}"
LOG="$(mktemp -t railway-pinggy.XXXXXX.log)"
SSH_PID=""

cleanup() {
  if [[ -n "$SSH_PID" ]] && kill -0 "$SSH_PID" 2>/dev/null; then
    kill "$SSH_PID" 2>/dev/null || true
    wait "$SSH_PID" 2>/dev/null || true
  fi
  rm -f "$LOG"
}
trap cleanup EXIT INT TERM

ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 -p 443 -R0:"127.0.0.1:${LOCAL_PORT}" tcp@a.pinggy.io \
  </dev/null >"$LOG" 2>&1 &
SSH_PID=$!

for _ in $(seq 1 30); do
  URL="$(grep -Eo 'tcp://[^[:space:]]+' "$LOG" | head -1 || true)"
  [[ -n "$URL" ]] && break
  if ! kill -0 "$SSH_PID" 2>/dev/null; then
    echo "Pinggy tunnel exited before publishing a URL:" >&2
    cat "$LOG" >&2
    exit 1
  fi
  sleep 1
done

if [[ -z "${URL:-}" ]]; then
  echo "Timed out waiting for the Pinggy tunnel URL." >&2
  cat "$LOG" >&2
  exit 1
fi

HOST="${URL#tcp://}"
HOST="${HOST%%:*}"
PORT="${URL##*:}"
echo "Tunnel ready: ${URL}"
echo "Use MQTT_HOST=${HOST} MQTT_PORT=${PORT}"

if [[ "${1:-}" == "--write-secrets" ]]; then
  cat >"$ROOT/esp32/secrets.h" <<EOF
#pragma once

// Generated locally by scripts/wokwi-tunnel.sh. Never commit this file.
#define WIFI_SSID "Wokwi-GUEST"
#define WIFI_PASSWORD ""
#define MQTT_HOST "${HOST}"
#define MQTT_PORT ${PORT}
#define MQTT_USER "esp32"
#define MQTT_PASS "${ESP32_PASS}"
#define DEVICE_ID "esp32"
#define DEVICE_ZONE "zone1"
EOF
  echo "Wrote esp32/secrets.h for the current tunnel."
fi

echo "Tunnel is live. Press Ctrl-C to stop it."
wait "$SSH_PID"
