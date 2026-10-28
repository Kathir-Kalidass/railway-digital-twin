# Academic Project Report PDF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a compiled academic PDF report "Railway Digital Twin with Wildlife Safety" (COEG / Anna University, Embedded Systems and IoT, Team 14) with real regenerated simulation screenshots and IEEE-style references.

**Architecture:** All report sources live in `docs/report/` (`report.tex` master, `sections/*.tex` per chapter, `figures/` for screenshots). Figures are regenerated live from the Godot 4.7.2 binary with the repo's own capture scripts under `xvfb-run`, then copied into `figures/`. The master file inputs the section files; one `pdflatex` pass caches refs, a second resolves them.

**Tech Stack:** LaTeX (pdflatex, no extra packages beyond what is installed), Godot 4.7.2 capture scripts, bash.

**Spec:** User conversation of 2026-10-25 (this plan is its only record): academic report, CEG Anna University header, Team 14 = 2023103546 Kathir Kalidass B, 2023103597 Malini R, 2023103600 Parthasarathi S, 2023103714 Paril T; mandatory chapters: Tools and Technology, Dashboards, Features and Functions Implemented, Screenshots of simulation/hardware, References; plus Architecture, Peripherals, Workflow, Hardware/Simulation; appendices for ACL matrix, test-gate evidence, run instructions. PDF format only as deliverable.

## Global Constraints

- Content source of truth: `README.md`, `IMPLEMENTATION.md`, `docs/OPERATIONS.md`, `docs/porting/acceptance.md`, `docs/superpowers/specs/*`, and the actual source files. Never state anything the repo does not evidence.
- Honesty rule: physical-hardware checklist items are "not run" (per `README.md`); real-model ML smoke "skipped, ML_STUB used". The report states this plainly.
- Every figure is a genuine capture of this simulation; no stock/mock images.
- Report must compile with `pdflatex` (installed) with zero errors and no unresolved `\ref`/`figure` names.
- Team data verbatim: COLLEGE OF ENGINEERING, GUINDY — ANNA UNIVERSITY, CHENNAI - 25; course: Embedded Systems and Internet of Things; Team: 14.
- Place the LaTeX under `docs/report/`; deliverable file: `docs/report/report.pdf`.

## Review Focus

- Unverifiable claims (invented stats, invented hardware results) — no test;Reviewer must grep each claim to `acceptance.md` or source. 
- Figures that silently fail to regenerate (capture script writes nothing / clean exit without PNG) — every capture task has a step verifying non-trivial PNG size at the documented output path under `/tmp/opencode/`, then copying into `figures/`.
- LaTeX compile breakage from unescaped characters (`_`, `&`, `#`, URLs) or duplicate figure labels — every content task ends with a compile step whose expected output is "no errors".
- Stale numbers (e.g., "backend 118/118" vs latest 141/141) — the report uses the **latest gate numbers from acceptance.md** (backend 141/141, Godot 42/42, ML 8/8, ESP32 native 16/16, flash 87.1%).

---

### Task 1: Regenerate and stage simulation screenshots

**Files:**
- Create: `/tmp/opencode/*.png` (transient), then Create: `docs/report/figures/*.png`

**Interfaces:**
- Consumes: `godot/tests/capture_*.gd` scripts + Godot binary at `/home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64`.
- Produces: figure filenames in `docs/report/figures/` used verbatim by Tasks 4–8: `double_track_overview.png`, `platform_after_topdown.png`, `platform_after_oblique.png`, `meet_randomized.png`, `crossover_after.png`, `camera_confirm.png`, `scene_animals*.png`.

- [ ] **Step 1: Run capture scripts under xvfb.** From repo root, for each script `capture_double_track.gd`, `capture_station.gd`, `capture_meet.gd`, `capture_camera_confirm.gd`, `capture_animals.gd`: `xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 --path godot --resolution 1440x900 --rendering-method gl_compatibility --script res://tests/<script>`
- [ ] **Step 2: Verify** each documented output PNG exists in `/tmp/opencode/` (script headers state exact paths) and is > 50 KB: `ls -la /tmp/opencode/*.png`. If a capture script produced nothing, read its header, fix the invocation, or substitute a neighboring capture script — do not fabricate.
- [ ] **Step 3: Copy** verified PNGs into `docs/report/figures/` with the fig names above.

### Task 2: Report skeleton and front matter

**Files:**
- Create: `docs/report/report.tex`, `docs/report/sections/00-front.tex` (title page + abstract), stub `sections/01-introduction.tex` … `sections/10-backmatter.tex` (empty prologue only)

**Interfaces:**
- Produces: `report.tex` `\input{sections/0X-...}` ordering used by all content tasks; documentclass `report`, options `12pt,a4paper`; packages: `graphicx`, `geometry`, `booktabs`, `setspace`, `titling` if dep-free, `hyperref` last, `array`, `tabularx`, `float`, `caption`; `\graphicspath{{figures/}}`.

- [ ] **Step 1: Write master `report.tex`** with title-page layout (institute masthead, course, team table with reg. numbers), abstract, `\tableofcontents`, `\listoffigures`, `\listoftables`, chapter input ordering 0-front, 01-introduction, 02-requirements, 03-architecture-and-workflow, 04-tools-and-technology, 05-hardware-simulation, 06-twin, 07-dashboards, 08-features, 09-results-conclusion, 10-backmatter (appendices A–C + references).
- [ ] **Step 2: Write `00-front.tex`'s abstract** ~1 page: what it is (educational digital twin for wildlife-safe rail ops), stack, staged safety chain NONE→SUSPECTED→CONFIRMED, verification numbers from acceptance.md, limitation statement, keywords.
- [ ] **Step 3: Compile check:** `cd docs/report && pdflatex -interaction=nonstopmode report.tex` twice. Expected: `No pages of output` errors = none; PDF opens. Commit.

### Task 3: Chapters 1–2 (Introduction; System requirements and phases)

**Files:**
- Create: `docs/report/sections/01-introduction.tex`, `sections/02-requirements.tex`

**Interfaces:**
- Consumes: README "Current scope" (Phase 1, Stage 2A, stadium phases 1–3), `docs/superpowers/specs/2026-10-18-railway-digital-twin-enhancement-design.md` for phase list; acceptance.md for verification numbers.
- Produces: chapter labels `cha:introduction` `cha:requirements` referenced in abstract/results.

- [ ] **Step 1:** 1 Introduction — 1.1 background (train-animal collisions, IoT+DT in modern rail), 1.2 objectives, 1.3 scope (educational-only safety disclaimer verbatim), 1.4 phased implementation outline (Stage A→E, 2A–2G, stadium Phases 1–3), 1.5 organization of the report.
- [ ] **Step 2:** 2 System requirements — 2.1 functional (per-phase FR table), 2.2 non-functional (security, fail-safe, reproducibility, performance), 2.3 hardware requirements (dev host, ESP32 devkit v1 optional), 2.4 software requirements table, 2.5 phases and stage gate mapping table. Table labels `tab:*`.
- [ ] **Step 3:** compile check; commit.

### Task 4: Chapter 3 (Architecture and workflow) with self-made diagrams

**Files:**
- Create: `docs/report/sections/03-architecture-workflow.tex`, `docs/report/figures/arch-block-diagram.pdf` (TikZ)
- (TikZ vs graphicx: if TikZ is unavailable, fall back to a LaTeX-only `mdframed`-style layered ASCII->box library. Verify TikZ availability first.)

**Interfaces:**
- Consumes: README architecture bullet list and ACL table; OPERATIONS.md; `backend/src` module list (config, auth, rbac, replay, audit, db, simulation, signalling, routes, meets, wrong_line, ingest, ml.js, bus, loop, mqtt); acceptance.md stage notes.
- Produces: figures `fig:arch-block`, `fig:dataflow`, tables `tab:acl-matrix` (this one referenced from Appendix A rather than duplicated).

- [ ] **Step 1:** draw block diagram in TikZ: React dashboard + Godot twin + ESP32 (clients) → Mosquitto broker (1883 TCP, 9001 WS) → Node.js trusted control plane → SQLite audit/replay registry; REST/WS path dashboard↔backend; retained state topics to twin.
- [ ] **Step 2:** create the MQTT topic/ACL matrix table verbatim from README's topic contract table (backend, godot, dashboard, esp32 columns: publish and subscribe topics).
- [ ] **Step 3:** create end-to-end sequence figure 3.2 (dashboard REST `/api/control` → backend envelope validation & timestamp ±5 min & replay registry → MQTT publish → twin reconciler targets, speed, signal, ESP32; twin Telemetry → backend state publish → dashboard WS snapshot).
- [ ] **Step 4:** compile check; commit.

### Task 5: Chapters 4 and 5 (Tools and technology; Hardware and simulation stack)

**Files:**
- Create: `sections/04-tools.tex`, `sections/05-hardware-simulation.tex`

**Interfaces:**
- Consumes: version pins from package.json, platformio.ini, `ml/requirements.txt`, docker-compose.yml, acceptance.md env line (Node 24, Godot 4.7.2, PlatformIO, Wokwi CLI v0.29.0, Pinggy).
- Produces: `tab:tools-stack`, `tab:broker-sec`, `tab:esp32-bom`.

- [ ] **Step 1:** 4 Tools & technology — subsection per layer: frontend (React 18.3.1, Vite 6, TS 5.7, lucide-react), backend (Node 22+/24, Express 4.21, better-sqlite3 13, bcryptjs 3, jsonwebtoken 9, mqtt.js 5.16), broker (Eclipse Mosquitto 2, ACL file, password_file), twin (Godot 4.7.2, LTS-derived Blender GLB assets), firmware (PlatformIO espressif32, PubSubClient 2.8, ArduinoJson 7, ESP32Servo, Adafruit SSD1306/GFX), ML (FastAPI 0.135, uvicorn, torch 2.10 / torchvision SSDLite320-MobileNetV3, PIL), devops (Docker Compose, dev-up.sh, verify-all.sh, Node test runner, pytest).
- [ ] **Step 2:** 5 Hardware and simulation stack — 5.1 ESP32 devkit v1 peripherals wiring table from `diagram.json` (red/green LEDs, buzzer, yellow pushbutton wildlife, fault pushbutton, SSD1306 OLED if present, servo if present), full subsystem = periphery overview; 5.2 Wokwi VPL cloud simulation (wokwi.toml, scenarios/wildlife.yaml), 5.3 Pinggy raw-TCP tunnel `scripts/wokwi-tunnel.sh --write-secrets`, 5.4 SNTP clock truth and `clockValid:false` gate, 5.5 firmware build result (87.1% flash), 5.6 manual Stage D checklist table PASS/Not-run with dates (physical honestly marked not run).
- [ ] **Step 3:** compile check; commit.

### Task 6: Chapter 6 (Digital twin world)

**Files:**
- Create: `sections/06-twin.tex`

**Interfaces:**
- Consumes: acceptance.md Stadium Phase 1 (1253.9822/1228.8495 m, 250 m straights, station 150–198 m, A@120, B@240), 2B double-track (UP r120/DOWN r116, 4 m spacing, island station, crossovers), LTS port notes `docs/porting/lts-port.md`, Blender assets (train/station GLBs, deer/elephant), `main.gd` key bindings (SPACE, R, F, Up/Down, B, C), camera director, HUD.
- Produces: figures 6.1 `double_track_overview.png`, 6.2 `platform_after_topdown.png`, 6.3 `platform_after_oblique.png`, 6.4 `crossover_after.png`, 6.5 `scene_animals*.png`.

- [ ] **Step 1:** sections 6.1 world composition (stadium loop geom, river + bridges, catenary, treeline), 6.2 tracks and block registry, 6.3 island station and interlocked crossovers with figure cross-refs, 6.4 level crossing barriers + alarm, 6.5 LTS-derived asset fleet + real-file verification (`test_real_assets`), 6.6 cameras and HUD (cinematic reel, cycle, wrong-line/map), 6.7 error/edge handling (validate then reconcile).
- [ ] **Step 2:** figures with captions per Task 1 result (cross-refs from fig labels of Task 1); verify no missing figure warnings in compile.
- [ ] **Step 3:** compile check; commit.

### Task 7: Chapters 7 and 8 (Dashboards; Features and functions implemented)

**Files:**
- Create: `sections/07-dashboards.tex`, `sections/08-features.tex`

**Interfaces:**
- Consumes: `web/src/App.tsx` (read it in this task's Step 1) — login, token state, train cards, block diagram, evidence badges (CAM/HUT), meet card, wrong-line panel, camera health; `main.gd` HUD in 3D (wrong-line text, meet countdown); acceptance.md Stage 2F badges, 2G meet card, Phase 2 wrong-line operator UI, Phase 3 camera health panel; IMPLEMENTATION.md RBAC roles.
- Produces: `tab:dashboard-roles`, figure 7.x optional screenshot if a framework-free 1440x900 browser capture exists; otherwise use only the App.tsx code-path screenshots described by App.tsx via LaTeX `verbatim` links. (No fabricated dashboard screenshot exists — wait for Step 1 results.)

- [ ] **Step 1:**實際 read App.tsx (900 lines-ish) and main.gd HUD sub-tree; list literally-visible dashboard panels and HUD text strings.
- [ ] **Step 2:** 7 Dashboards — 7.1 web dashboard for operators (role matrix RBAC table), 7.2 panels and data flows (auth → token; WS live snapshot; controls), 7.3 twin-side HUD, 7.4 diagnostics surfaces (setup script output, hackathon helper not present in App.tsx if not there; only list what Step 1 found).
- [ ] **Step 3:** 8 Features and functions implemented — master table mapping every shipped feature → module(s), test evidence (acceptance.md row),  and 8.7 edge cases handled (duplicate event ids, 413/429 rate limit, X-Block filtering, per acceptance.md "Spec closure audit").
- [ ] **Step 4:** compile check; commit.

### Task 9: Chapter 9, task 10 = results & conclusion; 10-backmatter.tex

**Files:**
- Create: `sections/09-results.tex`

**Interfaces:**
- Consumes: gates in acceptance.md (latest re-run 2026-10-23: backend 141/141, Godot 42/42, ML 8/8, ESP32 16/16, flash 87.1%), live path scenario results (T1/T3 hold at 320.1 m, near→confirmed flows), Stage D Wokwi PASS log lines (`STATE LOCAL WILDLIFE`).
- Produces: none downstream.

- [ ] **Step 1:** 9 Results, discussion and conclusion — automated-gate table (per surface × command × result), live end-to-end scenario walkthroughs (wrong-line hold, near→confirm, meet seed 4242), 9.3 team member contributions, 4.4 conclusion, 9.5 future scope (real-weights ML load, physical hardware validation, true GNSS/peripheral integration). Honest limitations subsection (ML_STUB in most tests, physical hardware not run, stop-distance is visualization only).
- [ ] **Step 2:** 10-backmatter.tex — in order: references (`thebibliography`, 10–14 IEEE-style entries: Godot 4 docs, Mosquitto 2, MQTT OASIS 5.0 spec, MQTT security recommendations, Wokwi docs, PlatformIO, Pinggy, JWT RFC 8725, torchvision SSDLite paper, Express 4, React 18, electron/Libre-TrainSim repo), acknowledgements page (institute, course, institute staff). Appendices land in Task 10, which continues this file.
- [ ] **Step 3:** compile check; commit.

### Task 10: Appendices and final gate

**Files:**
- Modify: `sections/10-backmatter.tex` (appendix A: expanded ACL topic JSON table; appendix B: full test-gate evidence table copied from `acceptance.md`; appendix C: run/setup instructions from README/OPERATIONS)

**Interfaces:**
- Consumes: README §Broker auth and ACLs table; acceptance.md tables; README local setup steps.

- [ ] **Step 1:** write appendix A/B/C content.
- [ ] **Step 2:** full compile: `cd docs/report && pdflatex -interaction=nonstopmode report.tex && pdflatex report.tex` (or xelatex if fonts need it). Expected: 0 errors, TOC stable, `grep -c "Warning: Reference" report.log` = 0, grep -c "File.*not found" = 0.
- [ ] **Step 3:** Commit. Final check: PDF page count ≥ 25, every figure file exists and is not 0-byte, deliverable sits at `docs/report/report.pdf`.

## Self-Review

- Spec coverage: mandatory audience + team verbatim (Task 2), all named chapters present (Tasks 3–9 TOC ordering), screenshots requirement = Task 1 + figure refs in 6/7, references = Task 9 step 2, appendices = Task 10. ✓
- Step scan: each step = write X precisely, compile, commit. No "add appropriate validation" leftovers. ✓
- Type consistency: figure filenames fixed in Task 1 and referenced by Tasks 6/7 identically. ✓
- Review Focus: honesty rule pinned by requiring the live Stage-D table to quote PASS/Not-run dates (Task 5) and the results chapter to read only from acceptance.md (Task 9). Compile gate per task = the compile step at every content task's end, so LaTeX breakage surfaces in the task that introduced it. Figure availability pinned by the >50 KB size check in Task 1. Stale numbers pinned by Global Constraints "latest gate numbers from acceptance.md" line, verified by Tasks 5, 9.
- Proportion: plan is shorter than the ~40-page report it produces. ✓
