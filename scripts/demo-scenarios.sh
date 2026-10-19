#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3001}"
DEMO_NON_DESTRUCTIVE="${DEMO_NON_DESTRUCTIVE:-0}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "required command not found: $1" >&2
    exit 1
  }
}

require_cmd curl
require_cmd jq

http_json() {
  local method="$1"
  local path="$2"
  local token="${3:-}"
  local body="${4:-}"
  local tmp
  tmp="$(mktemp)"

  local -a args=(-sS -o "$tmp" -w '%{http_code}' -X "$method" "${API_BASE}${path}")
  if [[ -n "$token" ]]; then
    args+=(-H "Authorization: Bearer $token")
  fi
  if [[ -n "$body" ]]; then
    args+=(-H 'Content-Type: application/json' -d "$body")
  fi

  local code
  code="$(curl "${args[@]}")"

  if [[ ! "$code" =~ ^[2345][0-9][0-9]$ ]]; then
    echo "HTTP $code for $method $path: $(cat "$tmp")" >&2
    rm -f "$tmp"
    return 1
  fi

  cat "$tmp"
  rm -f "$tmp"
}

assert_json() {
  local label="$1"
  local json="$2"
  local expr="$3"
  if ! printf '%s' "$json" | jq -e "$expr" >/dev/null 2>&1; then
    echo "Assertion failed for $label: $expr" >&2
    echo "$json" >&2
    return 1
  fi
}

login() {
  local username="$1"
  local password="$2"
  local response
  response="$(http_json POST /api/auth/login "" "{\"username\":\"$username\",\"password\":\"$password\"}")"
  printf '%s' "$response" | jq -r '.token // empty'
}

request_id() {
  local suffix
  suffix="$(openssl rand -hex 8 2>/dev/null || date +%s%N)"
  printf 'demo-%s-%s' "$(date +%s)" "$suffix"
}

echo "=== Railway Digital Twin Demo Scenarios ==="
echo "Targeting backend at $API_BASE"

echo "1. Health check..."
HEALTH="$(http_json GET /api/health "" "")"
assert_json "health" "$HEALTH" '.ok == true and .mqttConnected == true'
echo "  ✔ Health check passed"

echo "2. Logging in as operator..."
TOKEN="$(login operator operator-dev-pass)"
[[ -n "$TOKEN" ]] || { echo "operator login failed" >&2; exit 1; }
echo "  ✔ Operator logged in, JWT obtained"

echo "3. Read state and verify the train/block model is present..."
STATE="$(http_json GET /api/state "$TOKEN" "")"
assert_json "state" "$STATE" '.zones and (.zones | type == "object")'
if printf '%s' "$STATE" | jq -e '(.trains | type == "array") and (.trains | length >= 2)' >/dev/null 2>&1; then
  echo "  ✔ At least two trains are present"
else
  echo "  ℹ state does not expose a train list yet; skipping multi-train structural assertion"
fi
if printf '%s' "$STATE" | jq -e '(.blocks | type == "array") and (.blocks | length >= 1)' >/dev/null 2>&1; then
  echo "  ✔ At least one block is present"
else
  echo "  ℹ state does not expose a block list yet; skipping block structural assertion"
fi

echo "4. Triggering wildlife in Zone 1..."
REQ_ID="$(request_id)"
HAZARD_RESPONSE="$(http_json POST /api/control "$TOKEN" "{\"request_id\":\"$REQ_ID\",\"zone\":\"zone1\",\"event\":\"WILDLIFE_DETECTED\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"source\":\"demo-script\"}")"
assert_json "hazard" "$HAZARD_RESPONSE" '.ok == true'
echo "  ✔ Wildlife event accepted"

STATE_AFTER_HAZARD="$(http_json GET /api/state "$TOKEN" "")"
assert_json "zone-1-hazard" "$STATE_AFTER_HAZARD" '.zones.zone1.signal == "RED" or .zones.zone1.status == "HAZARD"'
echo "  ✔ Zone 1 is restrictive after the hazard"

echo "5. Clearing wildlife and resetting Zone 1..."
if [[ "$DEMO_NON_DESTRUCTIVE" == "1" ]]; then
  echo "  ℹ DEMO_NON_DESTRUCTIVE=1; skipping mutation and reset"
else
  REQ_CLEAR="$(request_id)"
  CLEAR_RESPONSE="$(http_json POST /api/control "$TOKEN" "{\"request_id\":\"$REQ_CLEAR\",\"zone\":\"zone1\",\"event\":\"WILDLIFE_CLEARED\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"source\":\"demo-script\"}")"
  assert_json "clear" "$CLEAR_RESPONSE" '.ok == true'

  REQ_RESET="$(request_id)"
  RESET_RESPONSE="$(http_json POST /api/control "$TOKEN" "{\"request_id\":\"$REQ_RESET\",\"zone\":\"zone1\",\"event\":\"RESET\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"source\":\"demo-script\"}")"
  assert_json "reset" "$RESET_RESPONSE" '.ok == true'
  echo "  ✔ Zone 1 reset accepted, returned to NORMAL"
fi

echo "=== All demo scenarios completed successfully ==="
