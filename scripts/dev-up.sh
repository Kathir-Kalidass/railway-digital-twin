#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/mosquitto_setup.sh"
docker compose -f "$ROOT/docker-compose.yml" up --build -d
echo "Backend: http://localhost:3001/api/health"
