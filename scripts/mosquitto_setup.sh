#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-$ROOT/.env}"

if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

: "${MQTT_GODOT_PASS:=godot-dev-pass}"
: "${MQTT_ESP32_PASS:=esp32-dev-pass}"
: "${MQTT_BACKEND_PASS:=backend-dev-pass}"
: "${MQTT_DASHBOARD_PASS:=dashboard-dev-pass}"

command -v docker >/dev/null 2>&1 || { echo "docker is required to generate Mosquitto passwords" >&2; exit 1; }

cd "$ROOT/mosquitto"
mkdir -p "$ROOT/mosquitto"

docker run --rm \
  -v "$ROOT/mosquitto:/work" \
  -e G="$MQTT_GODOT_PASS" \
  -e E="$MQTT_ESP32_PASS" \
  -e B="$MQTT_BACKEND_PASS" \
  -e D="$MQTT_DASHBOARD_PASS" \
  eclipse-mosquitto:2 sh -c '
    rm -f /work/password_file
    mosquitto_passwd -b -c /work/password_file godot "$G"
    mosquitto_passwd -b /work/password_file esp32 "$E"
    mosquitto_passwd -b /work/password_file backend "$B"
    mosquitto_passwd -b /work/password_file dashboard "$D"
    chmod 600 /work/password_file
  '

echo "Wrote $ROOT/mosquitto/password_file"
