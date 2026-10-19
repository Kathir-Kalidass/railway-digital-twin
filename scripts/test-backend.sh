#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/mosquitto_setup.sh"
cd "$ROOT"
docker compose up -d mqtt
for i in $(seq 1 30); do
  if docker compose exec -T mqtt mosquitto_sub -h 127.0.0.1 -p 1883 -u backend -P "${MQTT_BACKEND_PASS:-backend-dev-pass}" -t railway/zone1/train -C 1 -W 1 >/dev/null 2>&1; then break; fi
  sleep 1
done
npm --prefix backend test
