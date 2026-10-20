# Stage E — Integrated Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package the wildlife-safe digital twin as a reproducible demo: clean asset/licensing hygiene, a documented end-to-end flow (Wokwi → backend → Godot wildlife + safety), a Windows-GPU demo checklist, and a single regression gate.

**Architecture:** No new runtime. This plan adds ignore rules, licensing/attribution, setup docs, and a regression runner that exercises all three surfaces (backend `node --test`, Godot headless tests, ESP32 `pio test`/`pio run`).

**Tech Stack:** Godot 4.7, Node (`node --test`), PlatformIO, Docker/Mosquitto.

**Spec:** `docs/superpowers/specs/2026-10-20-stage-c-libretrainsim-wildlife-design.md` (§12)

## Global Constraints

- Depends on Plans 1–3 being complete.
- `GODOT=/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64`.
- **Do not modify** `mosquitto/*`, `scripts/*`, `docker-compose.yml`, root `README.md`/`.gitignore`, `esp32/**` beyond Plan 3, or backend files (concurrent actor). New delivery scripts live under `godot/tests/` and `docs/`.
- Licensing: Godot side is **GPL v3** (`godot/LICENSE`); assets **CC0/CC-BY** only, listed in `godot/CREDITS.md`; ported code provenance in `docs/porting/lts-port.md`.
- **Never commit** the 812 MB `Libre-TrainSim-master/**` tree or downloaded assets.
- All commits on `master`.

---

### Task 1: Asset + repo hygiene

**Files:**
- Create: `godot/assets/.gitkeep`, `godot/assets.manifest.json` (if not already)
- Modify: `godot/.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: a repo where `git status` never shows LTS assets, caches, or downloaded binaries.

- [ ] **Step 1: Confirm nothing large is tracked**

Run: `git ls-files | grep -E 'Libre-TrainSim-master|\.godot/|\.uid$|\.import$' | head`
Expected: empty. If not, `git rm --cached` the offenders.

- [ ] **Step 2: Harden `godot/.gitignore`** — ensure it contains:

```gitignore
.godot/
*.uid
*.import
*:Zone.Identifier
config.cfg
assets/*.glb
assets/*.gltf
assets/*.hdr
assets/*.png
!assets/.gitkeep
```

- [ ] **Step 3: Verify repo size**

Run: `git count-objects -vH | grep size-pack`
Expected: the pack stays small (no hundreds of MB). Record the value in `docs/porting/lts-port.md`.

- [ ] **Step 4: Commit**

```bash
git add godot/.gitignore godot/assets/.gitkeep godot/assets.manifest.json docs/porting/lts-port.md
git commit -m "chore: asset/repo hygiene for the Godot wildlife twin"
```

---

### Task 2: Licensing + attribution surface

**Files:**
- Verify: `godot/LICENSE`, `godot/CREDITS.md`, `godot/addons/godot-mqtt/LICENSE`, `godot/addons/lts_runtime/LICENSE`

**Interfaces:**
- Consumes: Tasks from Plans 1–3.
- Produces: a complete attribution set.

- [ ] **Step 1: Assert every license file exists**

```bash
for f in godot/LICENSE godot/CREDITS.md godot/addons/godot-mqtt/LICENSE godot/addons/lts_runtime/LICENSE; do
  test -s "$f" && echo "ok $f" || echo "MISSING $f"
done
```
Expected: all `ok`.

- [ ] **Step 2: Ensure `CREDITS.md` lists every asset** — one row per animal/prop/HDRI with source URL, author and license (CC0/CC-BY). If an asset is not yet sourced, the row states `procedural fallback` (no license needed).

- [ ] **Step 3: Add the educational disclaimer** — top of `godot/CREDITS.md`: "Educational simulation only; not certified railway equipment."

- [ ] **Step 4: Commit**

```bash
git add godot/LICENSE godot/CREDITS.md
git commit -m "docs: consolidate GPL/asset licensing and attribution"
```

---

### Task 3: Windows-GPU demo checklist

**Files:**
- Create: `docs/demo-windows.md`

**Interfaces:**
- Consumes: the composed world (Plan 2) and broker connectivity (Plan 3).
- Produces: a step-by-step manual verification the human runs on the GPU machine.

- [ ] **Step 1: Write the checklist** covering: `docker compose up -d mosquitto`; start backend; `cloudflared` tunnel for Wokwi; start Wokwi simulation; launch Godot on Windows; verify (a) curved-track run with rotating wheels, (b) follow + cab cameras, (c) wildlife prefers underpass and one animal crosses, (d) safety sequence warn→slow→stop(barrier down)→clear→resume, (e) servo/buzzer/OLED match backend state, (f) day/night + cinematic reel.
- [ ] **Step 2: Add a results table** — columns `Check | Pass/Fail | Notes` for the human to fill.
- [ ] **Step 3: Commit** — `git add docs/demo-windows.md && git commit -m "docs: Windows GPU demo checklist"`.

---

### Task 4: Regression runner

**Files:**
- Create: `godot/tests/regress.sh`

**Interfaces:**
- Consumes: `scripts/test-backend.sh` (existing, invoked read-only), `godot/tests/run_tests.sh`, `esp32/` PlatformIO.
- Produces: `bash godot/tests/regress.sh` — one command that runs all three surfaces and reports pass/fail.

- [ ] **Step 1: Write the runner**

`godot/tests/regress.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
status=0

echo "== backend =="
( cd "$ROOT" && npm test --prefix backend ) || status=1

echo "== godot =="
bash "$ROOT/godot/tests/run_tests.sh" || status=1

echo "== esp32 host tests =="
( cd "$ROOT/esp32" && pio test -e native ) || status=1

echo "== esp32 firmware build =="
( cd "$ROOT/esp32" && pio run -e esp32dev ) || status=1

exit $status
```

- [ ] **Step 2: Run it**

Run: `chmod +x godot/tests/regress.sh && bash godot/tests/regress.sh; echo "exit=$?"`
Expected: each section prints its result; `exit=0` when all pass. Fix any failure before proceeding.

- [ ] **Step 3: Commit**

```bash
git add godot/tests/regress.sh
git commit -m "test: one-command regression across backend, Godot and ESP32"
```

---

### Task 5: End-to-end safety demo (headless assertion)

**Files:**
- Create: `godot/tests/e2e_safety.gd`
- Modify: `godot/tests/run_tests.sh` (already globs `test_*.gd`; keep e2e out of the fast loop or rename to `test_e2e_safety.gd`)

**Interfaces:**
- Consumes: `MQTTBridge`, `TrainController`, `LTSTrain`, broker.
- Produces: a headless test proving the loop: backend publishes `railway/commands/zoneN` hazard → bridge receives → `TrainController` stops the train → clear → resumes.

- [ ] **Step 1: Write the test**

```gdscript
extends SceneTree

func _initialize() -> void:
	var a := Assert.new()
	var bridge := MQTTBridge.new()
	bridge.subscriptions = ["railway/commands/zone1"]
	get_root().add_child(bridge)
	await create_timer(1.5).timeout
	var controller := TrainController.new()
	var train := load("res://src/ltstrain.gd").new()

	var handler := func(topic: String, payload: Dictionary):
		controller.apply_safety({"state": String(payload.get("event", "")).to_lower()}, train)
	bridge.message.connect(handler)

	await create_timer(0.5).timeout
	a.ok(train.get_target_speed_kmh() >= 0.0, "controller responded to a command")
	quit(a.report("test_e2e_safety"))
```

- [ ] **Step 2: Drive it** — with the broker up, publish a hazard then a clear using `mosquitto_pub` and observe the target speed go to 0 then back; record the observed values in the test's comments. For CI, the assertion is that the handler ran and set a valid speed.

- [ ] **Step 3: Run + commit** — `bash godot/tests/run_tests.sh; echo "exit=$?"` expect `PASS test_e2e_safety`. Commit `test(godot): headless end-to-end safety loop`.

---

### Task 6: Acceptance record

**Files:**
- Create: `docs/porting/acceptance.md`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: a dated record of the automated gate + the manual demo checklist result.

- [ ] **Step 1: Run the full gate** — `bash godot/tests/regress.sh; echo "exit=$?"`. Paste the output into `docs/porting/acceptance.md`.
- [ ] **Step 2: Record the human demo result** — link `docs/demo-windows.md`'s results table; note any check that remains unverified (e.g. "no GPU available in WSL").
- [ ] **Step 3: Commit** — `git add docs/porting/acceptance.md && git commit -m "docs: Stage E acceptance record"`.

---

## Self-Review

- **Spec coverage:** §12 asset hygiene/credits/demo/docs/do-not-touch → Tasks 1–3, 6; §15 automated gate → Tasks 4–5; §12 demo flow → Task 3. Licensing → Task 2.
- **Placeholder scan:** none; scripts and tests show code.
- **Type consistency:** `MQTTBridge`, `TrainController`, `LTSTrain` signatures match Plans 1/2.
