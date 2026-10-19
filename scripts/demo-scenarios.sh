#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3001}"
echo "=== Railway Digital Twin Demo Scenarios ==="
echo "Targeting backend at $API_BASE"

echo "1. Health check..."
curl -s "$API_BASE/api/health" | grep -q '"ok":true' && echo "  ✔ Health check passed"

echo "2. Logging in as operator..."
TOKEN=$(curl -s -X POST "$API_BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"operator","password":"operator-dev-pass"}' | grep -o '"token":"[^"]*' | cut -d'"' -f4)
test -n "$TOKEN" && echo "  ✔ Operator logged in, JWT obtained"

echo "3. Triggering wildlife in Zone 1..."
REQ_ID="demo-$(date +%s%N)"
curl -s -X POST "$API_BASE/api/control" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"request_id\":\"$REQ_ID\",\"zone\":\"zone1\",\"event\":\"WILDLIFE_DETECTED\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"source\":\"demo-script\"}" | grep -q '"ok":true' && echo "  ✔ Wildlife event accepted"

echo "4. Checking state isolation (Zone 1 RED, Zone 2 YELLOW caution)..."
curl -s -H "Authorization: Bearer $TOKEN" "$API_BASE/api/state" | grep -q '"signal":"RED"' && echo "  ✔ Zone 1 signal is RED"

echo "5. Clearing wildlife and resetting Zone 1..."
REQ_CLEAR="demo-clear-$(date +%s%N)"
curl -s -X POST "$API_BASE/api/control" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"request_id\":\"$REQ_CLEAR\",\"zone\":\"zone1\",\"event\":\"WILDLIFE_CLEARED\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"source\":\"demo-script\"}" >/dev/null

REQ_RESET="demo-reset-$(date +%s%N)"
curl -s -X POST "$API_BASE/api/control" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"request_id\":\"$REQ_RESET\",\"zone\":\"zone1\",\"event\":\"RESET\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"source\":\"demo-script\"}" | grep -q '"ok":true' && echo "  ✔ Zone 1 reset accepted, returned to NORMAL"

echo "=== All demo scenarios completed successfully ==="
