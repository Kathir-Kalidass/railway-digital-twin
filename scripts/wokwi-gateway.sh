#!/usr/bin/env bash
set -euo pipefail

# Wokwi Private IoT Gateway helper.
#
# Starts the local wokwigw gateway (ws://localhost:9011) and writes
# esp32/secrets.h so the virtual ESP32 connects to this machine's broker via
# "host.wokwi.internal". Unlike scripts/wokwi-tunnel.sh (Pinggy), nothing
# expires: the gateway is a free local binary, no Wokwi account token needed.
#
# Usage: scripts/wokwi-gateway.sh [--write-secrets]
# Open the esp32/ project in Wokwi for VS Code (or wokwi.com with the private
# gateway enabled via F1) and start the simulator.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${WOKWIGW_BIN:-$HOME/.wokwi/bin/wokwigw}"
GATEWAY_PORT="${WOKWIGW_PORT:-9011}"
ESP32_PASS="${MQTT_ESP32_PASS:-esp32-dev-pass}"

if [[ ! -x "$BIN" ]]; then
  echo "wokwigw binary not found at $BIN" >&2
  echo "Download the latest Linux release from https://github.com/wokwi/wokwigw/releases" >&2
  echo "and place the 'wokwigw-linux' binary there." >&2
  exit 1
fi

if ss -ltn | grep -q ":${GATEWAY_PORT} "; then
  echo "Gateway already listening on port ${GATEWAY_PORT}."
else
  nohup "$BIN" --listenPort "${GATEWAY_PORT}" >/tmp/wokwigw.log 2>&1 &
  echo $! >/tmp/wokwigw.pid
  for _ in $(seq 1 10); do
    if ss -ltn | grep -q ":${GATEWAY_PORT} "; then break; fi
    sleep 1
  done
  if ss -ltn | grep -q ":${GATEWAY_PORT} "; then
    echo "Gateway listening on ws://localhost:${GATEWAY_PORT} (log: /tmp/wokwigw.log)."
  else
    echo "Gateway failed to start:" >&2
    cat /tmp/wokwigw.log >&2
    exit 1
  fi
fi

if [[ "${1:-}" == "--write-secrets" ]]; then
  cat >"$ROOT/esp32/secrets.h" <<EOF
#pragma once

// Generated locally by scripts/wokwi-gateway.sh. Never commit this file.
// Requires esp32/wokwi.toml [net] gateway = "ws://localhost:${GATEWAY_PORT}".
#define WIFI_SSID "Wokwi-GUEST"
#define WIFI_PASSWORD ""
#define MQTT_HOST "host.wokwi.internal"
#define MQTT_PORT 1883
#define MQTT_USER "esp32"
#define MQTT_PASS "${ESP32_PASS}"
#define DEVICE_ID "esp32"
#define DEVICE_ZONE "zone1"
EOF
  echo "Wrote esp32/secrets.h for the gateway (MQTT_HOST=host.wokwi.internal)."
  echo "Rebuild the firmware so the new secrets are baked in: (cd esp32 && pio run -e esp32dev)"
fi

echo "Gateway is live (background pid $(cat /tmp/wokwigw.pid 2>/dev/null || echo '?'))."
