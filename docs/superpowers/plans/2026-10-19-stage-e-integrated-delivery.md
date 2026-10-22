# Stage E — Integrated Delivery & Operational Readiness Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Complete and closed — accepted in Stage E acceptance records.

**Goal:** Make the complete backend + dashboard + Godot twin + ESP32 stack reproducible to configure, run, verify, demonstrate, and recover from a clean checkout — with accurate ACL docs, a deterministic demo script, verified gates, and clean repo hygiene.

**Architecture:** No authority changes. This stage consolidates configuration samples, readiness checks, the demo script, and documentation, and adds a gate/evidence matrix covering every prior stage (A, A2, B, C1, C2, D).

**Tech Stack:** Docker Compose, Mosquitto, Node.js backend, Vite/React dashboard, Godot 4.7, PlatformIO, Bash.

**Spec:** [`../specs/2026-10-19-stage-e-integrated-delivery-design.md`](../specs/2026-10-19-stage-e-integrated-delivery-design.md)

**Prerequisites:** A2 (S0), B, C1, C2, D implemented or explicitly marked *not run*.

## Global Constraints

- No authority changes; the backend remains the sole command/state/signal authority; dashboard MQTT credentials stay read-only.
- Preserve least-privilege ACLs; never enable anonymous access or a broad `railway/#` grant.
- No real secrets or generated local state in git; samples are placeholder-only.
- Never delete unrelated volumes/user data during setup or cleanup.
- Record exact commands, results, and environment; mark unavailable checks *not run* — never report an unexecuted hardware/Godot/Wokwi check as passed.
- Keep SQLite data in the existing `backend-data` named volume.

## File Structure

- Create `.env.sample`.
- Modify `scripts/dev-up.sh`, `scripts/mosquitto_setup.sh`, `scripts/demo-scenarios.sh`, `scripts/test-backend.sh`.
- Create `scripts/verify-all.sh` (gate runner).
- Modify `README.md`; create `docs/OPERATIONS.md`.
- Modify `.gitignore`.

---

### Task 1: Environment sample and hardened startup

**Files:**
- Create: `.env.sample`
- Modify: `scripts/dev-up.sh`
- Test: manual readiness

**Interfaces:**
- Produces: `.env.sample` with every variable `docker-compose.yml` consumes; `dev-up.sh` that fails fast on missing prerequisites and waits for readiness.

- [ ] **Step 1: Create `.env.sample`**

```dotenv
# Copy to .env (git-ignored) and set distinct development values.
MQTT_BACKEND_PASS=backend-dev-pass
JWT_SECRET=dev-insecure-secret-change-me
VIEWER_PASSWORD=viewer-dev-pass
OPERATOR_PASSWORD=operator-dev-pass
ADMIN_PASSWORD=admin-dev-pass
```

- [ ] **Step 2: Ensure `.env` is ignored**

Confirm `.gitignore` contains `.env` (it does). Add `.env.local` if used by tooling.

- [ ] **Step 3: Harden `dev-up.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v docker >/dev/null || { echo "docker is required"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "docker compose v2 is required"; exit 1; }
[ -f "$ROOT/.env" ] || echo "warning: .env not found; using compose dev defaults"
bash "$ROOT/scripts/mosquitto_setup.sh"
docker compose -f "$ROOT/docker-compose.yml" up --build -d
# readiness: backend health must report ok + mqttConnected
for i in $(seq 1 60); do
  if curl -fsS http://localhost:3001/api/health | grep -q '"ok":true'; then
    echo "backend ready: http://localhost:3001/api/health"; break
  fi
  [ "$i" = 60 ] && { echo "backend did not become ready"; exit 1; }
  sleep 1
done
```

Readiness must report dependency failure, not a success-shaped fallback (the health check must include `mqttConnected`).

- [ ] **Step 4: Verify from a clean state**

Run: `./scripts/dev-up.sh` then `curl -s http://localhost:3001/api/health`.
Expected: `{"ok":true,"mqttConnected":true}`.

- [ ] **Step 5: Commit**

```bash
git add .env.sample scripts/dev-up.sh
git commit -m "chore(delivery): env sample and hardened startup with readiness"
```

---

### Task 2: Broker setup script review

**Files:**
- Modify: `scripts/mosquitto_setup.sh`

- [ ] **Step 1: Fail fast on prerequisites**

Ensure the script checks for the `mosquitto_passwd` tool (or the container path used today), creates `mosquitto/password_file` with all four identities (`godot`, `esp32`, `backend`, `dashboard`) using env-provided or dev-default passwords, and exits non-zero with an actionable message if a prerequisite is missing. Never enable anonymous access.

- [ ] **Step 2: Verify ACL file is least-privilege**

Confirm `mosquitto/acl_file` reflects the **A2** matrix (Task 6 documents it): `godot` has **no** `zoneN/train` write and **reads** `railway/signal/+`; `dashboard` reads `railway/signal/+`; `backend` writes `railway/signal/+`. If unchanged from A2, no edit needed here.

- [ ] **Step 3: Verify a fresh setup rejects anonymous connections**

Run: `docker compose up -d mqtt` then `mosquitto_pub -h localhost -p 1883 -t railway/state -m x` (no credentials).
Expected: connection refused/not authorized.

- [ ] **Step 4: Commit (if changed)**

```bash
git add scripts/mosquitto_setup.sh
git commit -m "chore(delivery): fail-fast broker setup"
```

---

### Task 3: Harden the demo script (multi-train/block)

**Files:**
- Modify: `scripts/demo-scenarios.sh`

**Interfaces:**
- Produces: a demo that validates HTTP status and JSON (not substring success), uses unique request IDs, adds multi-train/block steps, supports a non-destructive mode, and cleans up only when safe.

- [ ] **Step 1: Replace substring success with strict checks**

Add helpers:

```bash
req() { # method path token body
  local method="$1" path="$2" token="$3" body="${4:-}"
  local args=(-sS -o /tmp/resp.$$ -w '%{http_code}' -X "$method" "$API_BASE$path")
  [ -n "$token" ] && args+=(-H "Authorization: Bearer $token")
  [ -n "$body" ] && args+=(-H 'Content-Type: application/json' -d "$body")
  local code; code="$(curl "${args[@]}")"
  if [ "$code" -ge 400 ]; then echo "HTTP $code for $method $path: $(cat /tmp/resp.$$)"; return 1; fi
  cat /tmp/resp.$$; rm -f /tmp/resp.$$
}

login() { req POST /api/auth/login "" "{\"username\":\"$1\",\"password\":\"$2\"}" | jq -r .token; }
```

Use `jq` for JSON assertions (`jq -e '.ok == true'`), and `set -euo pipefail` with `trap 'rm -f /tmp/resp.$$' EXIT`.

- [ ] **Step 2: Add A2 multi-train/block steps**

After login and health:
- read `/api/state`, assert `trains | length >= 2` and `blocks | length >= 1`;
- assert at least one block with a `GREEN` aspect and that occupy → the guarding block shows `YELLOW`/`RED` (allow for timing; assert the aspect domain, not a fixed value);
- optionally set a per-train speed: `POST /api/speed` with `{"zone":"zone1","trainId":"T1","speedKmh":40,"request_id":...}`.

- [ ] **Step 3: Non-destructive mode + safe cleanup**

Support `DEMO_NON_DESTRUCTIVE=1` to skip mutating steps. Only reset a zone after confirming via `/api/state` that the hazard it triggered is the one being cleared; never clear another operator's active hazard.

- [ ] **Step 4: Run against the live stack**

Run: `API_BASE=http://localhost:3001 ./scripts/demo-scenarios.sh`
Expected: every step prints ✔; script exits 0; state returns to NORMAL for the zones it touched.

- [ ] **Step 5: Commit**

```bash
git add scripts/demo-scenarios.sh
git commit -m "test(delivery): strict multi-train demo script with safe cleanup"
```

---

### Task 4: Gate runner script

**Files:**
- Create: `scripts/verify-all.sh`

**Interfaces:**
- Produces: a single script that runs each gate and prints a PASS/FAIL/NOT-RUN summary, continuing past failures to collect all evidence.

- [ ] **Step 1: Implement**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
declare -A RESULTS
run() { local name="$1"; shift; if "$@"; then RESULTS[$name]=PASS; else RESULTS[$name]=FAIL; fi; }
run backend   bash -c "cd '$ROOT' && npm --prefix backend test"
run web_build bash -c "cd '$ROOT/web' && npm run build"
run acl       bash "$ROOT/scripts/test-backend.sh"
run godot_headless bash -c "~/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path '$ROOT/godot' --quit"
printf '\n=== Gate results ===\n'
for k in "${!RESULTS[@]}"; do printf '%-16s %s\n' "$k" "${RESULTS[$k]}"; done
printf '%-16s %s\n' godot_visual "NOT RUN (Windows GPU)"
printf '%-16s %s\n' esp32_wokwi  "NOT RUN (Wokwi/physical)"
```

- [ ] **Step 2: Make executable and run**

Run: `chmod +x scripts/verify-all.sh && ./scripts/verify-all.sh`
Expected: prints results; hardware-only gates marked NOT RUN.

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-all.sh
git commit -m "test(delivery): add gate runner with evidence summary"
```

---

### Task 5: Operational documentation

**Files:**
- Create: `docs/OPERATIONS.md`
- Modify: `README.md`

- [ ] **Step 1: Write `docs/OPERATIONS.md`**

Cover: services/ports/runtimes; dependency install; startup/shutdown; health URLs and readiness expectations; the client identity + ACL matrix (A2-updated, see Task 6); credential generation/rotation; Docker-host vs Godot vs Wokwi vs physical networking (state that `localhost` on ESP32 is the device itself); diagnostics per component; safe recovery; how to identify stale state, restore connectivity, and clear a sensor fault **without bypassing backend reset validation**; the educational-only boundary, illustrative braking model, and missing TLS/credential provisioning.

- [ ] **Step 2: Update README**

Fix the "Requirements" (Godot 4.7, Node 22+/24) and add links to every stage spec (A, A2, B, C, D, E) and both C plans. Keep it a concise entry point that points to `docs/OPERATIONS.md`.

- [ ] **Step 3: Verify links resolve**

Run: `ls docs/superpowers/specs docs/superpowers/plans` and confirm every linked path exists.

- [ ] **Step 4: Commit**

```bash
git add docs/OPERATIONS.md README.md
git commit -m "docs(delivery): operations guide and README refresh"
```

---

### Task 6: Correct the ACL matrix everywhere

**Files:**
- Modify: `README.md`
- Modify: `mosquitto/acl_file` (only if it drifted from A2)

**Interfaces:**
- Produces: an ACL table identical to `mosquitto/acl_file` and to the A2 §7.3 matrix.

- [ ] **Step 1: Rewrite the README ACL table to match A2**

| Client | Publish | Subscribe |
|---|---|---|
| `backend` | `railway/state`, `railway/events`, `railway/alerts`, `railway/security/events`, `railway/commands/*`, `railway/speed/*`, `railway/zone*/signal`, `railway/signal/+` | `railway/zone*/wildlife`, `railway/telemetry/esp32` |
| `godot` | `railway/zone*/wildlife` | `railway/state`, `railway/commands/zone*`, `railway/speed/zone*`, `railway/zone*/signal`, `railway/signal/+` |
| `dashboard` | *(none)* | `railway/state`, `railway/events`, `railway/alerts`, `railway/signal/+` |
| `esp32` | `railway/telemetry/esp32` | `railway/commands/esp32` |

(Confirm exact topics against `mosquitto/acl_file` and adjust the table to match the file — the file is the source of truth.)

- [ ] **Step 2: Cross-check against the file**

Run: `cat mosquitto/acl_file` and reconcile every row. If the file is correct, only docs change.

- [ ] **Step 3: Commit (docs-only if the file is already correct)**

```bash
git add README.md mosquitto/acl_file
git commit -m "docs(delivery): correct least-privilege ACL matrix"
```

---

### Task 7: Release packaging and repository hygiene

**Files:**
- Modify: `.gitignore`, `README.md`, `docs/OPERATIONS.md`
- Verify: tracked files

- [ ] **Step 1: Scan tracked files for secrets/generated state**

Run:

```bash
git ls-files | grep -iE '\.env$|password_file|secrets\.h|config\.cfg$|\.db$|\.sqlite|\.wal$|\.shm$' || echo "no sensitive tracked files"
git ls-files godot/assets | head
```

Expected: no real secrets; only samples; `godot/config.cfg` and `esp32/secrets.h` untracked.

- [ ] **Step 2: Verify script executability and relative paths**

Run: `ls -l scripts/*.sh` and confirm each has the execute bit and uses `ROOT="$(cd "$(dirname "$0")/.." && pwd)"` rather than absolute paths.

- [ ] **Step 3: Verify asset manifest**

Confirm `godot/assets/CREDITS.md` accounts for every imported asset (or states none were imported and placeholders are used).

- [ ] **Step 4: Commit any hygiene fixes**

```bash
git add -A
git commit -m "chore(delivery): repo hygiene for release"
```

---

### Task 8: Architecture/data-flow documentation

**Files:**
- Modify: `docs/OPERATIONS.md` or `README.md`

- [ ] **Step 1: Add a data-flow diagram**

Add a Mermaid diagram showing: dashboard → authenticated REST → backend (validate/authorize/apply/audit) → retained MQTT state/signals → dashboard (read-only) + Godot (render) + ESP32 (consume command), and Godot/ESP32 → telemetry/wildlife → backend ingest. Make explicit: backend owns authority; dashboard MQTT is read-only.

- [ ] **Step 2: Validate the Mermaid renders**

Paste into a Markdown preview (or `npx @mermaid-js/mermaid-cli` if available); fix syntax until it renders.

- [ ] **Step 3: Commit**

```bash
git add README.md docs/OPERATIONS.md
git commit -m "docs(delivery): architecture and authority data-flow diagram"
```

---

### Task 9: Final acceptance run

**Files:**
- Modify: `docs/OPERATIONS.md` (evidence section)

- [ ] **Step 1: Clean-checkout rehearsal**

From a fresh clone/worktree: copy `.env.sample` → `.env`, run `./scripts/dev-up.sh`, `./scripts/verify-all.sh`.

- [ ] **Step 2: Run the full demo**

Run: `./scripts/demo-scenarios.sh`
Expected: all steps pass; multi-train/block steps pass; zones return to NORMAL.

- [ ] **Step 3: Record evidence**

In `docs/OPERATIONS.md`, record: exact commands, environment (OS, Docker, Node, Godot versions), gate results, and which manual checks were **not run** (Godot visual on Windows GPU; Wokwi/physical).

- [ ] **Step 4: Commit**

```bash
git add docs/OPERATIONS.md
git commit -m "docs(delivery): record final acceptance evidence"
```

---

## Self-Review

**Spec coverage:** reproducible setup (§3 → Tasks 1–2); config/security docs (§4 → Tasks 5–6); repeatable demo (§5 → Task 3); verification gates/evidence (§6 → Tasks 4, 9); release packaging/hygiene (§7 → Tasks 6–8); acceptance (§9 → Task 9). Authority rules (§2) are asserted in Tasks 3, 6, 8.

**Placeholder scan:** No `TBD`/`TODO`. Task 6 instructs reconciling docs against `mosquitto/acl_file` (the source of truth) rather than trusting the table, which is a concrete verification step. Task 3's A2 assertions deliberately check the aspect *domain* rather than a fixed value to avoid flakiness.

**Type consistency:** Script names (`dev-up.sh`, `mosquitto_setup.sh`, `demo-scenarios.sh`, `test-backend.sh`, `verify-all.sh`) are used consistently; the ACL matrix matches the A2 spec §7.3 and is cross-checked against the actual `acl_file`.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-19-stage-e-integrated-delivery.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks.

**2. Inline Execution** — execute in-session with checkpoints (`superpowers:executing-plans`).

**Note:** Stage E can only be fully verified once A2, B, C1, C2, and D are implemented. Run it last.
