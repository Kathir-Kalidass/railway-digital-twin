# Stage B — Authenticated Operations Dashboard (design)

Date: 2026-10-19
Status: approved (contracts verified against backend source)
Parent design: `docs/superpowers/specs/2026-10-18-railway-digital-twin-enhancement-design.md` (§7 Dashboard, §12 Delivery stages B)

## 1. Purpose

Replace the stale pre-Stage-A `web/` dashboard with the Stage B
authenticated operations dashboard described in the parent design's §7. The
current `web/src/App.tsx` targets the old unauthenticated REST surface
(`/api/state`, `/api/events`, `/api/command`) and therefore reports
"Backend unavailable" (401/404) and never shows a connected MQTT state. The
backend Stage A control plane is complete and is **not** changing in this
stage.

Success: an operator can log in, watch two zones live, and issue control
commands that flow REST → backend → MQTT and are reflected on the dashboard in
near real time; a viewer sees state only; an admin also sees the audit/security
feed.

## 2. Scope

**In scope**

- Login (JWT, in-memory) and logout; role-aware UI.
- Live state/events/alerts pushed over MQTT-over-WebSocket (read-only
  `dashboard` broker account).
- Two-zone visualization (signal aspects, occupancy, wildlife, sensor health).
- Train panel (speed, target, zone, stopping-distance estimate).
- Role-gated control panel: per-zone scenario commands and per-zone speed.
- Admin-only audit/security feed.
- ESP32/edge-controller panel.
- Connection/health status (broker + backend) with an offline marker.

**Out of scope (explicitly)**

- Any backend change (REST/MQTT contracts are consumed as-is).
- User-management UI (`users:manage`); only read-only audit is shown.
- Godot/ESP32 firmware (Stages C/D).
- Persisting the JWT (spec §7: memory only) or a refresh-token flow.
- Polling state/events/alerts/telemetry (push only). The only polls are the
  admin audit feed (5 s) and the backend health check (10 s), defined in §3.

## 3. Architecture and data flow

```
browser (React + TS + Vite)
 ├─ REST client ── Bearer JWT ─► backend :3001
 │     POST /api/auth/login  GET /api/me
 │     POST /api/control     POST /api/speed
 │     GET  /api/state       GET  /api/events   GET /api/audit   GET /api/health
 └─ mqtt.js over WebSocket ── user "dashboard" (read-only) ─► broker :9001
       subscribe: railway/state (retained) · railway/events · railway/alerts
                  railway/telemetry/esp32
```

- **Live source of truth is MQTT push** for `state`, `events`, `alerts`, and
  `esp32 telemetry`. No polling of those.
- On login the dashboard fetches `/api/state` and `/api/events` once for an
  immediate first paint / event history (events are not retained on the
  broker). The MQTT feed then streams updates; **state ordering is resolved by
  the `updatedAt` reconciliation rule in §9**.
- **Control is REST-only.** MQTT is read-only for the dashboard; the backend is
  the sole command/state publisher.
- Two lightweight REST polls run while logged in:
  - `GET /api/audit?limit=100` every 5 s (admin only) → audit/security feed.
  - `GET /api/health` every 10 s (any role) → the `backendUp` indicator.

## 4. Broker ACL change

The dashboard must receive live ESP32 telemetry, so one read line is added to
the `dashboard` user in `mosquitto/acl_file`:

```
user dashboard
topic read railway/state
topic read railway/events
topic read railway/alerts
topic read railway/telemetry/esp32
```

The WebSocket listener is already configured (`mosquitto/mosquitto.conf`:
`listener 9001 0.0.0.0` + `protocol websockets`). Only the ACL line above is a
change; it requires a broker restart (`docker compose restart mqtt` or
re-running `./scripts/dev-up.sh`). No password/user change is needed
(`dashboard` already exists in `password_file`).

## 5. Configuration

Vite env vars, each with a dev default so no `docker-compose.yml` change is
required (the web container runs the Vite dev server, so runtime env applies):

| Var | Default | Notes |
|---|---|---|
| `VITE_API_URL` | `http://localhost:3001` | existing |
| `VITE_MQTT_URL` | `ws://${location.hostname}:9001` | host-derived so it works on localhost and LAN |
| `VITE_MQTT_USERNAME` | `dashboard` | read-only broker account |
| `VITE_MQTT_PASSWORD` | `dashboard-dev-pass` | read-only; ships in the bundle by design (§7 parent spec, low risk) |

## 6. Module layout and interfaces

```
web/src/
├── lib/types.ts            # State, Zone, Train, Comm, EventRow, AlertRow, AuditRow, TelemetryRow, User, Role
├── lib/config.ts           # API_URL, MQTT_URL/USERNAME/PASSWORD (env + defaults)
├── lib/api.ts              # login, me, getState, getEvents, getAudit, control, setSpeed, health
├── lib/feed.ts             # createFeed(callbacks) -> { close }; wraps mqtt.js
├── context/AppContext.tsx  # auth + feed state + actions; useApp()
├── hooks/useTwinFeed.ts    # adapts createFeed to React; {state, events, alerts, telemetry, status}
├── components/…            # presentational
├── App.tsx                 # login gate + layout composition
└── style.css               # extended existing theme
```

Boundaries:

- `lib/*` are framework-free (browser APIs only; no React imports).
- `hooks/*` and `context/*` adapt `lib/*` to React.
- `components/*` are presentational and receive data/actions via `useApp()` or
  props.

### `lib/api.ts`

```ts
type Api = {
  login(username: string, password: string): Promise<{ token: string; user: User }>;
  me(token: string): Promise<User>;
  getState(token: string): Promise<State>;
  getEvents(token: string): Promise<EventRow[]>;
  getAudit(token: string, limit?: number): Promise<AuditRow[]>;
  control(token: string, envelope: CommandEnvelope): Promise<{ ok: true; state: State }>;
  setSpeed(token: string, zone: ZoneId, speedKmh: number): Promise<{ ok: true; state: State }>;
  health(): Promise<{ ok: boolean; mqttConnected: boolean }>;
};
```

Envelope handling (verified against `backend/src/routes/auth.js`):

- `login` returns `{ token, user: { username, role } }` — keep both.
- `me` returns `{ user: { id, username, role } }` — take `user` (drop `id`).
- `getState`/`getEvents`/`getAudit` return bare payloads (object / array).
- `control`/`setSpeed` return `{ ok: true, state }`.

Errors normalize to `ApiError { status: number; reason: string }` where
`reason = body.reason ?? body.error ?? 'request failed'`. Backend statuses
(verified): `401 {error:'unauthorized'}` (bad/expired token) and login failure
`401 {error:'invalid credentials'}`; `403 {error:'forbidden',reason}`;
`400 {error:'invalid command'|'duplicate'|'invalid speed',reason}`;
`409 {error:'transition rejected',reason}`.

### `lib/feed.ts`

```ts
type FeedStatus = 'connecting' | 'connected' | 'disconnected' | 'error';
type Feed = {
  close(): void;
};
function createFeed(opts: {
  url: string; username: string; password: string;
  onState(s: State): void;
  onEvent(e: EventRow): void;
  onAlert(a: AlertRow): void;
  onTelemetry(t: TelemetryRow): void;
  onStatus(status: FeedStatus, detail?: string): void;
}): Feed;
```

Uses `mqtt.connect(url, { username, password, reconnectPeriod: 3000,
connectTimeout: 5000, clientId: 'dashboard-' + crypto.randomUUID().slice(0,8) })`,
subscribes to the four topics, and maps `connect`/`close`/`offline`/`error`
events to `FeedStatus`. `close()` unsubscribes and ends the client.

**Inbound hardening:** every message payload is `JSON.parse`d inside try/catch;
malformed JSON is ignored and logged via `console.warn` (never logging
credentials). Before use, each payload is shape-checked per its topic — an
unknown `signal`/`status`/`overall` value or a missing required field causes
the message to be dropped rather than rendered. The feed never throws on bad
input.

**State ordering:** the initial `GET /api/state` snapshot and the retained
`railway/state` message both carry server-generated `updatedAt`. The feed and
context track the newest accepted `updatedAt` and only accept a state whose
`updatedAt >= lastAccepted` (ties allowed, last-write-wins). This prevents a
slow/late REST response from overwriting a newer live update. Same-server
clock makes this sound; the limitation (millisecond ties) is acceptable for
this project. Events are deduplicated by `event.id`.

### `context/AppContext.tsx`

```ts
type AppContextValue = {
  auth: { user: User | null; token: string | null; login(u,p): Promise<void>; logout(): void };
  feed: { state: State | null; events: EventRow[]; alerts: AlertRow[];
          telemetry: TelemetryRow[]; status: FeedStatus;
          backendUp: boolean; stale: boolean };
  actions: {
    issueCommand(zone: ZoneId, event: CommandType): Promise<void>;
    setSpeed(zone: ZoneId, speedKmh: number): Promise<void>;
    refreshAudit(): Promise<void>;
  };
  audit: AuditRow[];       // admin only; populated by 5s poll
  lastError: string | null;
};
```

`issueCommand` builds the envelope with a fresh
`request_id = crypto.randomUUID()`, `timestamp = new Date().toISOString()`,
`source = 'dashboard'`, `payload = {}`, then calls `api.control`.

## 7. Data contracts consumed

Source of truth: `backend/src/state.js`, `events.js`, `bus.js`, `ingest.js`,
`routes/*`.

**`railway/state` (retained)** and `GET /api/state`:

```ts
type State = {
  zones: Record<'zone1'|'zone2', {
    id: string; trainPresent: boolean; wildlifeDetected: boolean;
    sensorHealthy: boolean; signal: 'GREEN'|'YELLOW'|'RED';
    status: 'NORMAL'|'HAZARD'|'SENSOR_FAULT'|'RECOVERY_REQUIRED';
    targetSpeedKmh: number;
  }>;
  train: { zone: string; speedKmh: number; targetSpeedKmh: number; stoppingDistanceM: number };
  comm: { mqttConnected: boolean };
  overall: 'NORMAL'|'HAZARD'|'SENSOR_FAULT'|'RECOVERY_REQUIRED'|'COMM_LOST';
  lastEvent: string;
  updatedAt: string;
};
```

**`railway/events`** and `GET /api/events` item:

```ts
type EventRow = { id: string; time: string; type: string;
  zone?: string; actor?: string; result?: string; message?: string;
  source?: string; topic?: string };
```

**`railway/alerts`**:

```ts
type AlertRow = { source: string; severity: 'HIGH'|'MEDIUM'|'LOW';
  message: string; timestamp: string };
```

**`railway/telemetry/esp32`** (schema-tolerant):

```ts
type TelemetryRow = { zone?: string; sensorHealthy?: boolean;
  timestamp: string; raw: Record<string, unknown> };
```

**`GET /api/audit`** item (admin):

```ts
type AuditRow = { id: number; time: string; actor: string | null;
  role: string | null; action: string; zone: string | null;
  target: string | null; result: 'INFO'|'ACCEPTED'|'REJECTED'|'FORBIDDEN';
  reason: string | null; source: string | null };
```

`GET /api/audit` requires `audit:read` (admin) — a non-admin receives `403`.
The backend returns a plain array ordered newest-first and clamps `limit` to
1..500 (`backend/src/audit.js`). Audit-fetch failures are soft: keep the last
list and mark the feed stale; do not clear it.

**Auth**: `POST /api/auth/login` → `{ token, user: { username, role } }`;
`GET /api/me` → `{ user }`; `GET /api/health` → `{ ok, mqttConnected }`.

**Command envelope** (`POST /api/control`): `{ request_id, zone, event,
timestamp, source, payload }` where `event ∈ { WILDLIFE_DETECTED,
WILDLIFE_CLEARED, SENSOR_FAULT, SENSOR_RESTORED, RESET, TRAIN_ENTERED_ZONE,
TRAIN_LEFT_ZONE }`.

**Speed** (`POST /api/speed`): `{ zone, speedKmh }`, `speedKmh ∈ 0..80`.

## 8. UI / UX

- **LoginScreen** (unauthenticated): username/password, error text on 401.
  On success, token held in memory; feed starts.
- **TopBar**: brand; broker pill (`status`), backend pill (`backendUp` from
  `/api/health`), clock (`state.updatedAt`), user + role, logout. When broker
  status ≠ connected an "OFFLINE" marker shows and the whole live view is
  labelled "last known — may be stale" (`stale = true`).
- **SceneHeader**: existing stylized forest/rail scene extended to two lanes
  (ZONE 01 / ZONE 02) with three-aspect signal lamps per zone.
- **ZonePanel ×2** (`zone1`, `zone2`): signal aspect, status, train-present,
  wildlife, sensor health, target speed, per-zone overall tone
  (GREEN/YELLOW/RED derived from `signal`).
- **TrainPanel**: current zone, `speedKmh`, `stoppingDistanceM`, and the
  **active** target — `zones[train.zone].targetSpeedKmh` (the backend's
  `train.targetSpeedKmh` mirrors the current zone's target; `snapshot()` in
  `state.js`). Per-zone targets are shown independently inside each
  `ZonePanel`; the train panel must not imply both zone targets apply to the
  single train. `train.zone` always names a known zone (initialised to
  `zones[0]`, updated on `TRAIN_ENTERED_ZONE`); render defensively if it is
  ever unknown.
- **Esp32Panel**: comm link (`comm.mqttConnected` + broker status); per-zone
  sensor channel health (from `state.zones[*].sensorHealthy`); latest
  `telemetry` message per zone with age; recent `source==='esp32'` alerts.
  Shows an explicit "No telemetry received" until a device publishes; the
  absence of telemetry must never be rendered as "sensor healthy" — channel
  health is taken solely from `state.zones[*].sensorHealthy`.
- **EventFeed** (push): newest-first, 8 rows shown from `events`.
- **AlertFeed** (push): newest-first `alerts`, severity-toned; visible to all
  roles.
- **ControlPanel** — `operator`/`admin` only (hidden for `viewer`): per-zone
  command buttons (all seven events) and per-zone speed slider
  (0–80, step 4) + apply. Disabled while a command is in flight. Errors
  surfaced inline (403/400/409).
- **AuditFeed** — `admin` only: `audit` rows with result tone
  (`ACCEPTED`/`REJECTED`/`FORBIDDEN`); 5 s poll.

## 9. Behavior details

- **Command flow**: user clicks → `issueCommand` mints envelope → `api.control`
  → on `{ok,state}` apply the returned state through the §6 `updatedAt` rule
  (normally newer, so it paints immediately); the retained `railway/state`
  then reconciles. On error, show `reason`.
- **Replay/staleness**: fresh `request_id` + current `timestamp` per action
  satisfy `validateCommand` (5-minute staleness window) and `replay.check`.
- **Speed**: `applySpeed` + `railway/speed/zoneN`; dashboard reflects
  `targetSpeedKmh` via state.
- **Events history**: `/api/events` on login seeds the feed; `railway/events`
  appends. Dedupe by `event.id`.
- **State reconciliation**: the initial `/api/state`, each retained/live
  `railway/state`, and the `state` returned by `control`/`speed` all pass
  through the `updatedAt >= lastAccepted` rule (§6). A stale REST snapshot can
  never overwrite newer live state. Events dedupe by id (above).
- **Health poll**: `GET /api/health` every 10 s drives `backendUp`; a control/
  speed call that fails at the network layer also triggers an immediate
  re-check.
- **Audit poll**: starts on admin login, `setInterval` 5 s, cleared on logout;
  failures are soft (keep last data, mark stale).

## 10. Error handling and connection status

- Broker loss → `FeedStatus` `disconnected`/`offline`; pill + OFFLINE marker
  and `stale=true`; mqtt.js auto-reconnects (3 s). Last known state is retained
  (never blanked) and clearly marked stale.
- Backend unreachable → `backendUp=false`; control actions surface a network
  error; the feed keeps streaming if the broker is still up.
- **Malformed MQTT payloads** are dropped and logged (`console.warn`); they
  never throw and never expose credentials in the log.
- **Missing ESP32 telemetry** renders as "No telemetry received", never as
  healthy.
- API errors by status:
  - `401` → clear the in-memory token/session and return to the login screen.
  - `403` → **preserve** the session; show a permission error on the action.
  - `400` → show the reason (invalid command / duplicate `request_id` / invalid
    speed).
  - `409` → show "transition rejected" plus the backend reason.

## 11. Verification plan

- **Build gate**: `cd web && npm run build` (`tsc --noEmit && vite build`)
  passes. This is the parent spec's web gate; there is no web test runner.
- **Manual, against the live stack** (mqtt + backend up; `VITE_MQTT_*`
  defaults; broker restarted after the ACL edit):
  1. Login as `viewer` → state visible, no control panel, no audit feed.
  2. Login as `operator` → control panel; inject `WILDLIFE_DETECTED` on zone1
     → zone1 RED/HAZARD, zone2 YELLOW; `RESET` rejected (409) until cleared.
  3. Per-zone speed slider changes `targetSpeedKmh` via MQTT.
  4. Login as `admin` → audit feed shows ACCEPTED/REJECTED/FORBIDDEN rows,
     refreshed every 5 s.
  5. Stop the broker → OFFLINE marker; restart → auto-reconnect, state
     reconciles.
  6. ESP32 panel shows per-zone sensor health; shows no-telemetry state until a
     publisher exists (Stage D).

**Acceptance checklist (all must hold before Stage B is "done"):**

- [ ] `npm run build` passes.
- [ ] `viewer`/`operator`/`admin` each see the correct panels.
- [ ] Login failure (401) and expired-token (401 on a later call) return to
      the login screen.
- [ ] All four MQTT subscriptions work over WebSockets (state, events, alerts,
      telemetry/esp32).
- [ ] The dashboard cannot publish to MQTT (ACL grants it no write topic).
- [ ] The seven command types map to the exact backend envelope.
- [ ] Duplicate `event.id`s do not create duplicate rows.
- [ ] A stale REST state cannot overwrite newer live state (`updatedAt` rule).
- [ ] Per-zone targets stay consistent with the active train panel.
- [ ] Broker stop/start produces a visible OFFLINE → connected transition.
- [ ] Audit polling starts only for admins and stops on logout.
- [ ] Malformed MQTT payloads and missing telemetry are handled safely.

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| `mqtt` v5 bundling in Vite | Uses supported browser build; verified by `vite build` |
| Dashboard broker creds in bundle | Account is read-only by ACL; acceptable per parent spec |
| ACL change requires restart | Documented; manual checklist includes restart |
| ESP32 telemetry absent until Stage D | Panel degrades gracefully (explicit empty state) |
| Clock skew breaks timestamp validation | Use client `Date.now()`; 5-min window is generous |
| Shared broker credential readable from the bundle | Read-only ACL; acceptable for local demo. For any remote/LAN deployment use `wss://` + TLS and reassess the shared credential. |
| `mqtt` browser build differs from Node | Import the package's browser entry; verify in a real browser (a green `vite build` alone is not proof). |

## 13. Open decisions (resolved)

- **Zone-scoped speed**: per-zone (`POST /api/speed`, `railway/speed/zoneN`),
  matching the parent spec §14.
- **Audit refresh**: 5 s poll while admin is logged in.
- **ESP32 panel**: include; add `topic read railway/telemetry/esp32` to the
  dashboard ACL and subscribe for raw telemetry.
- **Visual direction**: keep the existing dark theme/scene, extended to two
  zones.
- **Broker config**: Vite env vars with dev defaults (host-derived WS URL).
- **Backend health**: explicit `GET /api/health` poll every 10 s (plus an
  immediate check after a failed control call) drives `backendUp`; not a
  last-observed-only flag.
- **State reconciliation**: newest server `updatedAt` wins (`>= lastAccepted`);
  a late REST snapshot cannot overwrite newer live state.
- **Per-zone vs train speed**: zone targets are shown independently; the train
  panel shows the active zone's target only.
