#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
else
  echo "warning: $ENV_FILE not found; using compose defaults"
fi

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "docker compose v2 is required" >&2; exit 1; }

# Host mosquitto must not fight the compose broker over port 1883.
# It is masked system-wide (2026-10: sudo systemctl mask mosquitto.service);
# if it ever gets re-enabled/unmasked, stop it here so compose owns 1883.
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet mosquitto.service; then
  echo "host mosquitto is running and holds port 1883; stopping it (mask it permanently with: sudo systemctl mask mosquitto.service)"
  sudo systemctl stop mosquitto.service || true
fi

bash "$ROOT/scripts/mosquitto_setup.sh" "$ENV_FILE"
docker compose -f "$ROOT/docker-compose.yml" up --build -d --remove-orphans

for i in $(seq 1 60); do
  if curl -fsS "http://localhost:3001/api/health" | grep -q '"ok":true' && \
     curl -fsS "http://localhost:3001/api/health" | grep -q '"mqttConnected":true'; then
    echo "backend ready: http://localhost:3001/api/health"
    exit 0
  fi
  sleep 1
done

echo "backend did not become ready within 60s" >&2
exit 1
