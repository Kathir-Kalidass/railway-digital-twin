# Stage B Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stale `web/` dashboard with an authenticated two-zone operations dashboard that reads live state/events/alerts/telemetry over MQTT-over-WebSocket and issues control commands over authenticated REST.

**Architecture:** A framework-free `lib/` layer (typed REST client + MQTT feed) feeds a single React `AppContext` (auth + feed + actions). Presentational components render the two zones, train, ESP32, feeds, and role-gated controls. The backend is unchanged; the only non-web change is one Mosquitto ACL read line.

**Tech Stack:** React 18 + TypeScript (strict) + Vite 6, `mqtt` v5 (browser WebSocket), `lucide-react`. Plain CSS (existing `style.css`), no CSS framework.

**Spec:** `docs/superpowers/specs/2026-10-19-stage-b-dashboard-design.md`

## Global Constraints

- **Frontend-only change:** only `web/**` and the single ACL line in `mosquitto/acl_file`. Do **not** modify `backend/**`, `godot/**`, `docker-compose.yml`, `scripts/**`, or `mosquitto/mosquitto.conf`.
- **No new test runner.** The project has no web test framework and the spec (§11) fixes the web gate as `npm run build` (`tsc --noEmit && vite build`) plus a manual checklist. Do **not** add Jest/Vitest. Each task's cycle is: write code → `npm run build` (must pass) → focused manual verification → commit.
- TypeScript `strict` is on; `tsconfig.json` `include: ["src"]`. Keep imports type-correct.
- Reuse existing CSS classes in `web/src/style.css` where possible; append new classes at the end of the file.
- Reuse existing `lucide-react` icons (already a dependency).
- React 18: use `createRoot` (already in `main.tsx`); do not add `react-router` — the app has a single authenticated view.
- Conventional commits, scoped `web` (e.g. `feat(web): ...`, `chore(web): ...`), matching repo history.
- Broker/backend are expected to be running for manual verification: `./scripts/dev-up.sh` (or `docker compose up -d`) plus `cd backend && npm start`. Dev users: `viewer`/`viewer-dev-pass`, `operator`/`operator-dev-pass`, `admin`/`admin-dev-pass`.

---

### Task 1: Foundation — dependency, types, config

**Files:**
- Modify: `web/package.json` (add `mqtt`)
- Create: `web/src/lib/types.ts`
- Create: `web/src/lib/config.ts`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - Types: `ZoneId`, `Role`, `Signal`, `ZoneStatus`, `Overall`, `CommandType`, `FeedStatus`, `Zone`, `Train`, `Comm`, `TwinState`, `EventRow`, `AlertRow`, `TelemetryRow`, `AuditRow`, `User`, `CommandEnvelope`; consts `ZONES: ZoneId[]`, `COMMAND_TYPES: CommandType[]`, `COMMAND_EVENTS: Set<CommandType>`.
  - `config: { apiUrl: string; mqttUrl: string; mqttUsername: string; mqttPassword: string }`.

- [ ] **Step 1: Add the `mqtt` dependency**

Edit `web/package.json` dependencies to include `"mqtt": "^5.10.1"` (keep the file single-line JSON style, comma-separated). Then:

```bash
cd web && npm install
```

Expected: installs without error; `web/node_modules/mqtt` exists.

- [ ] **Step 2: Create `web/src/lib/types.ts`**

```ts
export type ZoneId = 'zone1' | 'zone2';
export type Role = 'viewer' | 'operator' | 'admin';
export type Signal = 'GREEN' | 'YELLOW' | 'RED';
export type ZoneStatus = 'NORMAL' | 'HAZARD' | 'SENSOR_FAULT' | 'RECOVERY_REQUIRED';
export type Overall = ZoneStatus | 'COMM_LOST';
export type FeedStatus = 'connecting' | 'connected' | 'disconnected' | 'error';

export type CommandType =
  | 'WILDLIFE_DETECTED'
  | 'WILDLIFE_CLEARED'
  | 'SENSOR_FAULT'
  | 'SENSOR_RESTORED'
  | 'RESET'
  | 'TRAIN_ENTERED_ZONE'
  | 'TRAIN_LEFT_ZONE';

export const ZONES: ZoneId[] = ['zone1', 'zone2'];
export const COMMAND_TYPES: CommandType[] = [
  'WILDLIFE_DETECTED',
  'WILDLIFE_CLEARED',
  'SENSOR_FAULT',
  'SENSOR_RESTORED',
  'RESET',
  'TRAIN_ENTERED_ZONE',
  'TRAIN_LEFT_ZONE',
];
export const COMMAND_EVENTS = new Set<CommandType>(COMMAND_TYPES);

export interface Zone {
  id: string;
  trainPresent: boolean;
  wildlifeDetected: boolean;
  sensorHealthy: boolean;
  signal: Signal;
  status: ZoneStatus;
  targetSpeedKmh: number;
}

export interface Train {
  zone: string;
  speedKmh: number;
  targetSpeedKmh: number;
  stoppingDistanceM: number;
}

export interface Comm {
  mqttConnected: boolean;
}

export interface TwinState {
  zones: Record<string, Zone>;
  train: Train;
  comm: Comm;
  overall: Overall;
  lastEvent: string;
  updatedAt: string;
}

export interface EventRow {
  id: string;
  time: string;
  type: string;
  zone?: string;
  actor?: string;
  result?: string;
  message?: string;
  source?: string;
  topic?: string;
}

export interface AlertRow {
  source: string;
  severity: 'HIGH' | 'MEDIUM' | 'LOW' | string;
  message: string;
  timestamp: string;
}

export interface TelemetryRow {
  zone?: string;
  sensorHealthy?: boolean;
  timestamp: string;
  raw: Record<string, unknown>;
}

export interface AuditRow {
  id: number;
  time: string;
  actor: string | null;
  role: string | null;
  action: string;
  zone: string | null;
  target: string | null;
  result: 'INFO' | 'ACCEPTED' | 'REJECTED' | 'FORBIDDEN' | string;
  reason: string | null;
  source: string | null;
}

export interface User {
  username: string;
  role: Role;
}

export interface CommandEnvelope {
  request_id: string;
  zone: ZoneId;
  event: CommandType;
  timestamp: string;
  source: string;
  payload: Record<string, unknown>;
}
```

- [ ] **Step 3: Create `web/src/lib/config.ts`**

```ts
function env(key: string, fallback: string): string {
  const value = import.meta.env[key as keyof ImportMetaEnv] as string | undefined;
  return value && value.length > 0 ? value : fallback;
}

function defaultBrokerUrl(): string {
  const host = typeof window !== 'undefined' ? window.location.hostname : 'localhost';
  return `ws://${host}:9001`;
}

export const config = {
  apiUrl: env('VITE_API_URL', 'http://localhost:3001'),
  mqttUrl: env('VITE_MQTT_URL', defaultBrokerUrl()),
  mqttUsername: env('VITE_MQTT_USERNAME', 'dashboard'),
  mqttPassword: env('VITE_MQTT_PASSWORD', 'dashboard-dev-pass'),
};
```

- [ ] **Step 4: Build (type-check + bundle)**

Run: `cd web && npm run build`
Expected: PASS (exit 0). If `import.meta.env` indexing errors, cast: `const anyEnv = import.meta.env as Record<string, string | undefined>;` and index that.

- [ ] **Step 5: Commit**

```bash
git add web/package.json web/package-lock.json web/src/lib/types.ts web/src/lib/config.ts
git commit -m "feat(web): add shared types and runtime config for Stage B dashboard"
```

---

### Task 2: REST client (`lib/api.ts`)

**Files:**
- Create: `web/src/lib/api.ts`

**Interfaces:**
- Consumes: `config` (Task 1), types (Task 1).
- Produces:
  - `class ApiError extends Error { status: number }`.
  - `api.login(username, password): Promise<{ token: string; user: User }>`
  - `api.me(token): Promise<User>`
  - `api.getState(token): Promise<TwinState>`
  - `api.getEvents(token): Promise<EventRow[]>`
  - `api.getAudit(token, limit?): Promise<AuditRow[]>`
  - `api.control(token, envelope): Promise<{ ok: true; state: TwinState }>`
  - `api.setSpeed(token, zone, speedKmh): Promise<{ ok: true; state: TwinState }>`
  - `api.health(): Promise<{ ok: boolean; mqttConnected: boolean }>`

- [ ] **Step 1: Create `web/src/lib/api.ts`**

```ts
import { config } from './config';
import type {
  AuditRow, CommandEnvelope, EventRow, Role, TwinState, User, ZoneId,
} from './types';

export class ApiError extends Error {
  status: number;
  constructor(status: number, reason: string) {
    super(reason);
    this.name = 'ApiError';
    this.status = status;
  }
}

interface RequestOptions {
  method?: string;
  token?: string;
  body?: unknown;
}

async function request<T>(path: string, opts: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;

  const method = opts.method ?? (opts.body ? 'POST' : 'GET');
  let res: Response;
  try {
    res = await fetch(`${config.apiUrl}${path}`, {
      method,
      headers,
      body: opts.body ? JSON.stringify(opts.body) : undefined,
    });
  } catch {
    throw new ApiError(0, 'Network error — backend unreachable');
  }

  const text = await res.text();
  let body: unknown;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = undefined;
    }
  }

  if (!res.ok) {
    const record = (body ?? {}) as { reason?: unknown; error?: unknown };
    const reason = record.reason ?? record.error ?? `Request failed (${res.status})`;
    throw new ApiError(res.status, String(reason));
  }

  return body as T;
}

export const api = {
  async login(username: string, password: string): Promise<{ token: string; user: User }> {
    return request<{ token: string; user: User }>('/api/auth/login', { body: { username, password } });
  },

  async me(token: string): Promise<User> {
    const r = await request<{ user: { id: number; username: string; role: Role } }>('/api/me', { token });
    return { username: r.user.username, role: r.user.role };
  },

  getState(token: string): Promise<TwinState> {
    return request<TwinState>('/api/state', { token });
  },

  getEvents(token: string): Promise<EventRow[]> {
    return request<EventRow[]>('/api/events', { token });
  },

  getAudit(token: string, limit = 100): Promise<AuditRow[]> {
    return request<AuditRow[]>(`/api/audit?limit=${limit}`, { token });
  },

  control(token: string, envelope: CommandEnvelope): Promise<{ ok: true; state: TwinState }> {
    return request<{ ok: true; state: TwinState }>('/api/control', { token, body: envelope });
  },

  setSpeed(token: string, zone: ZoneId, speedKmh: number): Promise<{ ok: true; state: TwinState }> {
    return request<{ ok: true; state: TwinState }>('/api/speed', { token, body: { zone, speedKmh } });
  },

  health(): Promise<{ ok: boolean; mqttConnected: boolean }> {
    return request<{ ok: boolean; mqttConnected: boolean }>('/api/health');
  },
};
```

- [ ] **Step 2: Build**

Run: `cd web && npm run build`
Expected: PASS.

- [ ] **Step 3: Manual smoke check against the running backend**

Run (backend must be up on :3001):

```bash
cd web && node -e "fetch('http://localhost:3001/api/health').then(r=>r.json()).then(j=>console.log(j))"
```

Expected: prints `{ ok: true, mqttConnected: true }`. (This validates the endpoint the client hits; the client wrapper itself is exercised in Task 4.)

- [ ] **Step 4: Commit**

```bash
git add web/src/lib/api.ts
git commit -m "feat(web): add typed REST client with ApiError normalization"
```

---

### Task 3: MQTT feed (`lib/feed.ts`)

**Files:**
- Create: `web/src/lib/feed.ts`

**Interfaces:**
- Consumes: types (Task 1).
- Produces: `createFeed(opts: FeedOptions): Feed`; `parseState(raw: unknown): TwinState | null`; types `FeedOptions`, `Feed`.

- [ ] **Step 1: Create `web/src/lib/feed.ts`**

```ts
import mqtt, { type MqttClient } from 'mqtt';
import type {
  AlertRow, EventRow, FeedStatus, Signal, TelemetryRow, TwinState, ZoneStatus,
} from './types';

const TOPIC_STATE = 'railway/state';
const TOPIC_EVENTS = 'railway/events';
const TOPIC_ALERTS = 'railway/alerts';
const TOPIC_TELEMETRY = 'railway/telemetry/esp32';

const SIGNALS: Signal[] = ['GREEN', 'YELLOW', 'RED'];
const STATUSES: ZoneStatus[] = ['NORMAL', 'HAZARD', 'SENSOR_FAULT', 'RECOVERY_REQUIRED'];

export interface FeedOptions {
  url: string;
  username: string;
  password: string;
  onState(state: TwinState): void;
  onEvent(event: EventRow): void;
  onAlert(alert: AlertRow): void;
  onTelemetry(telemetry: TelemetryRow): void;
  onStatus(status: FeedStatus, detail?: string): void;
}

export interface Feed {
  close(): void;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

export function parseState(raw: unknown): TwinState | null {
  if (!isRecord(raw) || !isRecord(raw.zones)) return null;
  for (const zone of Object.values(raw.zones)) {
    if (!isRecord(zone)) return null;
    if (!SIGNALS.includes(zone.signal as Signal)) return null;
    if (!STATUSES.includes(zone.status as ZoneStatus)) return null;
  }
  if (!isRecord(raw.train) || !isRecord(raw.comm)) return null;
  if (typeof raw.updatedAt !== 'string') return null;
  return raw as unknown as TwinState;
}

export function createFeed(opts: FeedOptions): Feed {
  const client: MqttClient = mqtt.connect(opts.url, {
    username: opts.username,
    password: opts.password,
    reconnectPeriod: 3000,
    connectTimeout: 5000,
    clientId: `dashboard-${crypto.randomUUID().slice(0, 8)}`,
  });

  opts.onStatus('connecting');

  client.on('connect', () => {
    opts.onStatus('connected');
    client.subscribe(
      [TOPIC_STATE, TOPIC_EVENTS, TOPIC_ALERTS, TOPIC_TELEMETRY],
      { qos: 0 },
      (err) => {
        if (err) opts.onStatus('error', err.message);
      },
    );
  });
  client.on('reconnect', () => opts.onStatus('connecting'));
  client.on('close', () => opts.onStatus('disconnected'));
  client.on('offline', () => opts.onStatus('disconnected'));
  client.on('error', (err) => opts.onStatus('error', err.message));

  client.on('message', (topic, buffer) => {
    let data: unknown;
    try {
      data = JSON.parse(buffer.toString());
    } catch {
      console.warn(`[feed] dropped malformed payload on ${topic}`);
      return;
    }

    try {
      if (topic === TOPIC_STATE) {
        const state = parseState(data);
        if (state) opts.onState(state);
        else console.warn('[feed] dropped invalid state payload');
        return;
      }
      if (topic === TOPIC_EVENTS) {
        if (isRecord(data) && typeof data.id === 'string') opts.onEvent(data as unknown as EventRow);
        return;
      }
      if (topic === TOPIC_ALERTS) {
        if (isRecord(data)) {
          opts.onAlert({
            source: String(data.source ?? 'unknown'),
            severity: String(data.severity ?? 'LOW'),
            message: String(data.message ?? ''),
            timestamp: String(data.timestamp ?? new Date().toISOString()),
          });
        }
        return;
      }
      if (topic === TOPIC_TELEMETRY) {
        if (isRecord(data)) {
          opts.onTelemetry({
            zone: typeof data.zone === 'string' ? data.zone : undefined,
            sensorHealthy: typeof data.sensorHealthy === 'boolean' ? data.sensorHealthy : undefined,
            timestamp: new Date().toISOString(),
            raw: data,
          });
        }
      }
    } catch (err) {
      console.warn('[feed] handler error', err);
    }
  });

  return {
    close() {
      try {
        client.end(true);
      } catch {
        /* ignore */
      }
    },
  };
}
```

- [ ] **Step 2: Build**

Run: `cd web && npm run build`
Expected: PASS. If TS complains about `crypto.randomUUID`, it is available in the DOM lib (`lib: ["ES2022","DOM","DOM.Iterable"]`); if not, fall back to `Math.random().toString(16).slice(2, 10)`.

- [ ] **Step 3: Verify the browser entry resolves**

Run:

```bash
cd web && node -e "const p=require('./node_modules/mqtt/package.json'); console.log(p.version, JSON.stringify(p.browser)||'no-browser-field', p.exports? '[has exports]':'')"
```

Expected: prints the mqtt version and either a browser field or `[has exports]`. This confirms a browser build is published (the actual in-browser connection is verified in Task 5/9 — a green build alone is not proof, per the spec's risk note).

- [ ] **Step 4: Commit**

```bash
git add web/src/lib/feed.ts
git commit -m "feat(web): add MQTT-over-WebSocket feed with payload validation"
```

---

### Task 4: React state layer (`hooks/useTwinFeed.ts`, `context/AppContext.tsx`)

**Files:**
- Create: `web/src/hooks/useTwinFeed.ts`
- Create: `web/src/context/AppContext.tsx`
- Modify: `web/src/main.tsx` (wrap `<App/>` in `<AppProvider>`)

**Interfaces:**
- Consumes: `config` (Task 1), `api`/`ApiError` (Task 2), `createFeed`/`Feed` (Task 3), types (Task 1).
- Produces:
  - `useTwinFeed(enabled: boolean): { state; events; alerts; telemetry; status; stale; applyRestState(s); applyRestEvents(rows) }`
  - `AppProvider` and `useApp(): AppContextValue` with `{ auth, feed, actions, audit, lastError, clearError }` (shape defined in spec §6).

- [ ] **Step 1: Create `web/src/hooks/useTwinFeed.ts`**

```ts
import { useCallback, useEffect, useRef, useState } from 'react';
import { config } from '../lib/config';
import { createFeed, type Feed } from '../lib/feed';
import type { AlertRow, EventRow, FeedStatus, TelemetryRow, TwinState } from '../lib/types';

const MAX_EVENTS = 200;
const MAX_ALERTS = 100;
const MAX_TELEMETRY = 50;

export interface TwinFeed {
  state: TwinState | null;
  events: EventRow[];
  alerts: AlertRow[];
  telemetry: TelemetryRow[];
  status: FeedStatus;
  stale: boolean;
  applyRestState(state: TwinState): void;
  applyRestEvents(rows: EventRow[]): void;
}

export function useTwinFeed(enabled: boolean): TwinFeed {
  const [state, setState] = useState<TwinState | null>(null);
  const [events, setEvents] = useState<EventRow[]>([]);
  const [alerts, setAlerts] = useState<AlertRow[]>([]);
  const [telemetry, setTelemetry] = useState<TelemetryRow[]>([]);
  const [status, setStatus] = useState<FeedStatus>('disconnected');
  const feedRef = useRef<Feed | null>(null);

  const applyRestState = useCallback((incoming: TwinState) => {
    setState((prev) => {
      const next = incoming.updatedAt || '';
      const current = prev?.updatedAt || '';
      if (prev && current && next && next < current) return prev;
      return incoming;
    });
  }, []);

  const applyRestEvents = useCallback((rows: EventRow[]) => {
    setEvents((prev) => {
      const seen = new Set(prev.map((e) => e.id));
      const merged = [...prev];
      for (const row of rows) {
        if (!seen.has(row.id)) {
          merged.push(row);
          seen.add(row.id);
        }
      }
      merged.sort((a, b) => (a.time < b.time ? 1 : a.time > b.time ? -1 : 0));
      return merged.slice(0, MAX_EVENTS);
    });
  }, []);

  useEffect(() => {
    if (!enabled) {
      feedRef.current?.close();
      feedRef.current = null;
      return;
    }
    const feed = createFeed({
      url: config.mqttUrl,
      username: config.mqttUsername,
      password: config.mqttPassword,
      onState: applyRestState,
      onEvent: (event) =>
        setEvents((prev) => (prev.some((e) => e.id === event.id) ? prev : [event, ...prev].slice(0, MAX_EVENTS))),
      onAlert: (alert) => setAlerts((prev) => [alert, ...prev].slice(0, MAX_ALERTS)),
      onTelemetry: (t) => setTelemetry((prev) => [t, ...prev].slice(0, MAX_TELEMETRY)),
      onStatus: (next, detail) => {
        if (detail) console.warn('[feed]', next, detail);
        setStatus(next);
      },
    });
    feedRef.current = feed;
    return () => {
      feed.close();
      feedRef.current = null;
    };
  }, [enabled, applyRestState]);

  return {
    state,
    events,
    alerts,
    telemetry,
    status,
    stale: status === 'disconnected' || status === 'error',
    applyRestState,
    applyRestEvents,
  };
}
```

- [ ] **Step 2: Create `web/src/context/AppContext.tsx`**

```tsx
import {
  createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode,
} from 'react';
import { api, ApiError } from '../lib/api';
import { useTwinFeed } from '../hooks/useTwinFeed';
import type {
  AlertRow, AuditRow, CommandEnvelope, CommandType, EventRow, FeedStatus,
  TelemetryRow, TwinState, User, ZoneId,
} from '../lib/types';

export interface AppContextValue {
  auth: {
    user: User | null;
    token: string | null;
    login(username: string, password: string): Promise<void>;
    logout(): void;
  };
  feed: {
    state: TwinState | null;
    events: EventRow[];
    alerts: AlertRow[];
    telemetry: TelemetryRow[];
    status: FeedStatus;
    stale: boolean;
    backendUp: boolean;
  };
  actions: {
    issueCommand(zone: ZoneId, event: CommandType): Promise<void>;
    setSpeed(zone: ZoneId, speedKmh: number): Promise<void>;
    refreshAudit(): Promise<void>;
  };
  audit: AuditRow[];
  lastError: string | null;
  clearError(): void;
}

const AppContext = createContext<AppContextValue | null>(null);

export function useApp(): AppContextValue {
  const value = useContext(AppContext);
  if (!value) throw new Error('useApp must be used within <AppProvider>');
  return value;
}

export function AppProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [audit, setAudit] = useState<AuditRow[]>([]);
  const [backendUp, setBackendUp] = useState(false);
  const [lastError, setLastError] = useState<string | null>(null);

  const twin = useTwinFeed(Boolean(token));

  const clearError = useCallback(() => setLastError(null), []);

  const handleError = useCallback((error: unknown) => {
    if (error instanceof ApiError) {
      if (error.status === 401) {
        setToken(null);
        setUser(null);
        setAudit([]);
        setLastError('Session expired — please sign in again.');
        return;
      }
      setLastError(error.message);
      return;
    }
    setLastError(error instanceof Error ? error.message : 'Unexpected error');
  }, []);

  const login = useCallback(async (username: string, password: string) => {
    try {
      const result = await api.login(username, password);
      setToken(result.token);
      setUser(result.user);
      setLastError(null);
    } catch (error) {
      handleError(error);
      throw error;
    }
  }, [handleError]);

  const logout = useCallback(() => {
    setToken(null);
    setUser(null);
    setAudit([]);
    setLastError(null);
  }, []);

  // Seed state + event history once after login.
  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    (async () => {
      try {
        const snapshot = await api.getState(token);
        if (!cancelled) twin.applyRestState(snapshot);
      } catch (error) {
        if (!cancelled) handleError(error);
      }
      try {
        const history = await api.getEvents(token);
        if (!cancelled) twin.applyRestEvents(history);
      } catch {
        /* events history is best-effort */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [token, twin.applyRestState, twin.applyRestEvents, handleError]);

  // Backend health poll (public endpoint) every 10 s.
  useEffect(() => {
    let alive = true;
    const check = async () => {
      try {
        await api.health();
        if (alive) setBackendUp(true);
      } catch {
        if (alive) setBackendUp(false);
      }
    };
    check();
    const id = setInterval(check, 10000);
    return () => {
      alive = false;
      clearInterval(id);
    };
  }, []);

  // Audit poll (admin only) every 5 s.
  useEffect(() => {
    if (!token || user?.role !== 'admin') {
      setAudit([]);
      return;
    }
    let alive = true;
    const load = async () => {
      try {
        const rows = await api.getAudit(token);
        if (alive) setAudit(rows);
      } catch {
        /* soft failure: keep last list, do not clear */
      }
    };
    load();
    const id = setInterval(load, 5000);
    return () => {
      alive = false;
      clearInterval(id);
    };
  }, [token, user]);

  const issueCommand = useCallback(
    async (zone: ZoneId, event: CommandType) => {
      if (!token) return;
      const envelope: CommandEnvelope = {
        request_id: crypto.randomUUID(),
        zone,
        event,
        timestamp: new Date().toISOString(),
        source: 'dashboard',
        payload: {},
      };
      try {
        const result = await api.control(token, envelope);
        twin.applyRestState(result.state);
      } catch (error) {
        handleError(error);
        throw error;
      }
    },
    [token, twin.applyRestState, handleError],
  );

  const setSpeed = useCallback(
    async (zone: ZoneId, speedKmh: number) => {
      if (!token) return;
      try {
        const result = await api.setSpeed(token, zone, speedKmh);
        twin.applyRestState(result.state);
      } catch (error) {
        handleError(error);
        throw error;
      }
    },
    [token, twin.applyRestState, handleError],
  );

  const refreshAudit = useCallback(async () => {
    if (!token || user?.role !== 'admin') return;
    try {
      setAudit(await api.getAudit(token));
    } catch {
      /* soft */
    }
  }, [token, user]);

  const value = useMemo<AppContextValue>(
    () => ({
      auth: { user, token, login, logout },
      feed: {
        state: twin.state,
        events: twin.events,
        alerts: twin.alerts,
        telemetry: twin.telemetry,
        status: twin.status,
        stale: twin.stale,
        backendUp,
      },
      actions: { issueCommand, setSpeed, refreshAudit },
      audit,
      lastError,
      clearError,
    }),
    [
      user, token, login, logout, twin.state, twin.events, twin.alerts, twin.telemetry,
      twin.status, twin.stale, backendUp, issueCommand, setSpeed, refreshAudit, audit,
      lastError, clearError,
    ],
  );

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}
```

- [ ] **Step 3: Wrap the app in `AppProvider` (`web/src/main.tsx`)**

```tsx
import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import { AppProvider } from './context/AppContext';
import './style.css';
createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <AppProvider>
      <App />
    </AppProvider>
  </React.StrictMode>,
);
```

- [ ] **Step 4: Build**

Run: `cd web && npm run build`
Expected: PASS. (App still renders the old dashboard at this point — that is replaced in Task 5.)

- [ ] **Step 5: Commit**

```bash
git add web/src/hooks/useTwinFeed.ts web/src/context/AppContext.tsx web/src/main.tsx
git commit -m "feat(web): add twin feed hook and app context (auth, feed, actions, polls)"
```

---

### Task 5: App shell and login (`LoginScreen`, `TopBar`, `App.tsx`)

**Files:**
- Create: `web/src/components/LoginScreen.tsx`
- Create: `web/src/components/TopBar.tsx`
- Modify: `web/src/App.tsx` (rewrite as the authenticated shell)

**Interfaces:**
- Consumes: `useApp` (Task 4), `ZONES`/types (Task 1).
- Produces: default-exported `LoginScreen`, `TopBar`; `App` renders `LoginScreen` when unauthenticated and the `shell` layout when authenticated (placeholder sections for panels added in later tasks).

- [ ] **Step 1: Create `web/src/components/LoginScreen.tsx`**

```tsx
import { useState, type FormEvent } from 'react';
import { LogIn, TrainFront } from 'lucide-react';
import { useApp } from '../context/AppContext';

export default function LoginScreen() {
  const { auth, lastError, clearError } = useApp();
  const [username, setUsername] = useState('operator');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    clearError();
    try {
      await auth.login(username.trim(), password);
    } catch {
      /* surfaced through lastError */
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="login-wrap">
      <form className="login-card" onSubmit={onSubmit}>
        <div className="brand">
          <div className="brandicon"><TrainFront size={22} /></div>
          <div>
            <div className="eyebrow">DIGITAL TWIN / SAFETY SYSTEMS</div>
            <h1>Forest Railway Operations</h1>
          </div>
        </div>
        <p className="login-sub">Sign in to the operations dashboard.</p>
        <label className="login-field">
          Username
          <input value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" />
        </label>
        <label className="login-field">
          Password
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
          />
        </label>
        {lastError && <div className="login-error">{lastError}</div>}
        <button className="primary full" type="submit" disabled={busy}>
          {busy ? 'Signing in…' : <><LogIn size={16} /> Sign in</>}
        </button>
        <p className="login-hint">Dev users: viewer / operator / admin (see README for passwords).</p>
      </form>
    </main>
  );
}
```

- [ ] **Step 2: Create `web/src/components/TopBar.tsx`**

```tsx
import { Clock3, LogOut, Server, TrainFront, Wifi, WifiOff } from 'lucide-react';
import { useApp } from '../context/AppContext';

export default function TopBar() {
  const { auth, feed } = useApp();
  const connected = feed.status === 'connected';
  const updatedAt = feed.state ? new Date(feed.state.updatedAt).toLocaleTimeString() : '--:--:--';

  return (
    <header className="topbar">
      <div className="brand">
        <div className="brandicon"><TrainFront size={22} /></div>
        <div>
          <div className="eyebrow">DIGITAL TWIN / SAFETY SYSTEMS</div>
          <h1>Forest Railway Operations</h1>
        </div>
      </div>
      <div className="topmeta">
        <span className={`pill ${connected ? 'ok' : 'warn'}`}>
          <span className="dot" />
          {connected ? <><Wifi size={12} /> MQTT CONNECTED</> : <><WifiOff size={12} /> MQTT {feed.status.toUpperCase()}</>}
        </span>
        <span className={`pill ${feed.backendUp ? 'ok' : 'warn'}`}>
          <Server size={12} /> {feed.backendUp ? 'BACKEND OK' : 'BACKEND DOWN'}
        </span>
        <span className="clock"><Clock3 size={14} /> {updatedAt}</span>
        <span className="user-chip">{auth.user?.username} · {auth.user?.role}</span>
        <button className="ghost" onClick={auth.logout}><LogOut size={14} /> Sign out</button>
      </div>
    </header>
  );
}
```

- [ ] **Step 3: Rewrite `web/src/App.tsx`**

```tsx
import { AlertTriangle } from 'lucide-react';
import { useApp } from './context/AppContext';
import LoginScreen from './components/LoginScreen';
import TopBar from './components/TopBar';

export default function App() {
  const { auth, feed } = useApp();

  if (!auth.user) return <LoginScreen />;

  return (
    <main className="shell">
      <TopBar />
      {feed.stale && (
        <div className="error">
          <AlertTriangle size={17} /> Connection lost — showing last known state. Reconnecting…
        </div>
      )}
      <section className="zone-grid">
        <div className="panel"><div className="empty">Zone panels render here.</div></div>
        <div className="panel"><div className="empty">Zone panels render here.</div></div>
      </section>
      <footer>
        <span>MQTT bridge · REST API · Godot 4</span>
        <span className="disclaimer">EDUCATIONAL SIMULATION ONLY</span>
      </footer>
    </main>
  );
}
```

- [ ] **Step 4: Build**

Run: `cd web && npm run build`
Expected: PASS.

- [ ] **Step 5: Manual verification (login, roles, offline marker)**

With broker + backend up (`./scripts/dev-up.sh`, `cd backend && npm start`) and `cd web && npm run dev`:

1. Open http://localhost:5173 → login form is shown.
2. Login with a bad password → an error message appears, no shell.
3. Login `viewer`/`viewer-dev-pass` → shell appears; TopBar shows `MQTT CONNECTED` and `BACKEND OK` once the WS handshake completes (may briefly show `CONNECTING`).
4. Stop the broker (`docker compose stop mqtt`) → TopBar shows `MQTT DISCONNECTED`, the "Connection lost…" banner appears. Restart (`docker compose start mqtt`) → within ~3 s it returns to `MQTT CONNECTED` and the banner clears.

- [ ] **Step 6: Commit**

```bash
git add web/src/components/LoginScreen.tsx web/src/components/TopBar.tsx web/src/App.tsx
git commit -m "feat(web): add authenticated shell with login and connection status"
```

---

### Task 6: Monitoring panels (`Metric`, `SceneHeader`, `ZonePanel`, `TrainPanel`, `Esp32Panel`)

**Files:**
- Create: `web/src/components/Metric.tsx`
- Create: `web/src/components/SceneHeader.tsx`
- Create: `web/src/components/ZonePanel.tsx`
- Create: `web/src/components/TrainPanel.tsx`
- Create: `web/src/components/Esp32Panel.tsx`
- Modify: `web/src/App.tsx` (render the panels)
- Modify: `web/src/style.css` (append classes)

**Interfaces:**
- Consumes: `useApp` (Task 4), `Zone`/`TwinState`/`ZONES` (Task 1).
- Produces: default-exported `Metric`, `SceneHeader`, `ZonePanel({ zone, label })`, `TrainPanel({ state })`, `Esp32Panel()`.

- [ ] **Step 1: Create `web/src/components/Metric.tsx`**

```tsx
import type { ReactNode } from 'react';

export default function Metric({
  icon, label, value, sub, tone = '',
}: {
  icon: ReactNode; label: string; value: string; sub: string; tone?: string;
}) {
  return (
    <div className="metric">
      <div className={`metric-icon ${tone}`}>{icon}</div>
      <div className="metric-label">{label}</div>
      <div className={`metric-value ${tone}`}>{value}</div>
      <div className="metric-sub">{sub}</div>
    </div>
  );
}
```

- [ ] **Step 2: Create `web/src/components/SceneHeader.tsx`**

```tsx
import { useApp } from '../context/AppContext';
import { ZONES } from '../lib/types';

export default function SceneHeader() {
  const { feed } = useApp();
  return (
    <section className="scene-zones">
      {ZONES.map((zoneId) => {
        const zone = feed.state?.zones[zoneId];
        const aspect = zone?.signal?.toLowerCase() ?? 'green';
        return (
          <div className="scene-lane" key={zoneId}>
            <div className="sun" />
            <div className="forest f1">♠ ♠ ♠ ♠ ♠</div>
            <div className="rail rail1" />
            <div className="rail rail2" />
            <div className={`train ${zone?.trainPresent ? 'present' : ''}`}>
              <div className="train-window" />
              <div className="train-light" />
            </div>
            <div className={`signal ${aspect}`}><i /><i /><i /></div>
            {zone?.wildlifeDetected && <div className="hazard-marker visible">WILDLIFE ZONE</div>}
            <div className="scene-label">
              <span>ZONE {zoneId.slice(-1)}</span>
              <b>FOREST CORRIDOR</b>
            </div>
          </div>
        );
      })}
    </section>
  );
}
```

- [ ] **Step 3: Create `web/src/components/ZonePanel.tsx`**

```tsx
import { AlertTriangle, CheckCircle2, Gauge, Leaf, Radio, TrainFront } from 'lucide-react';
import type { ReactNode } from 'react';
import type { Zone } from '../lib/types';

function tone(zone: Zone): 'red' | 'amber' | 'green' {
  if (zone.signal === 'RED') return 'red';
  if (zone.signal === 'YELLOW') return 'amber';
  return 'green';
}

function Row({ icon, label, value, tone: rowTone }: {
  icon: ReactNode; label: string; value: string; tone?: string;
}) {
  return (
    <div className="zone-row">
      <span className="zr-label">{icon} {label}</span>
      <span className={`zr-value ${rowTone ?? ''}`}>{value}</span>
    </div>
  );
}

export default function ZonePanel({ zone, label }: { zone: Zone; label: string }) {
  const t = tone(zone);
  return (
    <div className="panel zone-card">
      <div className="panel-head">
        <div>
          <div className="eyebrow">{label}</div>
          <h3>{zone.status.replaceAll('_', ' ')}</h3>
        </div>
        <div className={`signal-stack ${t}`}>
          <i className={zone.signal === 'RED' ? 'on red' : ''} />
          <i className={zone.signal === 'YELLOW' ? 'on amber' : ''} />
          <i className={zone.signal === 'GREEN' ? 'on green' : ''} />
        </div>
      </div>
      <div className="zone-rows">
        <Row icon={<Radio size={14} />} label="Signal" value={zone.signal} tone={t} />
        <Row icon={<TrainFront size={14} />} label="Train present" value={zone.trainPresent ? 'YES' : 'NO'} />
        <Row icon={<Leaf size={14} />} label="Wildlife" value={zone.wildlifeDetected ? 'INTRUSION' : 'CLEAR'} tone={zone.wildlifeDetected ? 'red' : 'green'} />
        <Row
          icon={zone.sensorHealthy ? <CheckCircle2 size={14} /> : <AlertTriangle size={14} />}
          label="Sensor"
          value={zone.sensorHealthy ? 'HEALTHY' : 'FAULT'}
          tone={zone.sensorHealthy ? 'green' : 'red'}
        />
        <Row icon={<Gauge size={14} />} label="Target speed" value={`${zone.targetSpeedKmh} km/h`} />
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Create `web/src/components/TrainPanel.tsx`**

```tsx
import { Gauge, TrainFront } from 'lucide-react';
import Metric from './Metric';
import type { TwinState } from '../lib/types';

export default function TrainPanel({ state }: { state: TwinState | null }) {
  if (!state) return null;
  const activeZone = state.zones[state.train.zone];
  const activeTarget = activeZone ? activeZone.targetSpeedKmh : state.train.targetSpeedKmh;

  return (
    <div className="panel">
      <div className="panel-head">
        <div>
          <div className="eyebrow">TRAIN</div>
          <h3>{state.train.zone.toUpperCase()}</h3>
        </div>
        <TrainFront size={19} />
      </div>
      <div className="metric-grid inner">
        <Metric icon={<Gauge />} label="SPEED" value={`${state.train.speedKmh} km/h`} sub="live" />
        <Metric icon={<Gauge />} label="ACTIVE TARGET" value={`${activeTarget} km/h`} sub={`zone ${state.train.zone}`} />
        <Metric icon={<Gauge />} label="STOP DISTANCE" value={`${state.train.stoppingDistanceM} m`} sub="estimate" />
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Create `web/src/components/Esp32Panel.tsx`**

```tsx
import { AlertTriangle, Cpu } from 'lucide-react';
import { useApp } from '../context/AppContext';
import { ZONES } from '../lib/types';

export default function Esp32Panel() {
  const { feed } = useApp();
  const { state, telemetry, alerts } = feed;
  const espAlerts = alerts.filter((a) => a.source === 'esp32').slice(0, 4);

  const latestByZone = new Map<string, (typeof telemetry)[number]>();
  for (const entry of telemetry) {
    if (entry.zone) latestByZone.set(entry.zone, entry);
  }

  return (
    <div className="panel">
      <div className="panel-head">
        <div>
          <div className="eyebrow">ESP32 EDGE CONTROLLER</div>
          <h3>{state?.comm.mqttConnected ? 'Link up' : 'Link down'}</h3>
        </div>
        <Cpu size={19} />
      </div>
      <div className="zone-rows">
        {ZONES.map((zoneId) => {
          const healthy = state?.zones[zoneId]?.sensorHealthy;
          const latest = latestByZone.get(zoneId);
          const healthyTone = healthy === false ? 'red' : healthy === true ? 'green' : '';
          return (
            <div className="zone-row" key={zoneId}>
              <span className="zr-label">{zoneId.toUpperCase()} sensor</span>
              <span className={`zr-value ${healthyTone}`}>
                {healthy === undefined ? 'UNKNOWN' : healthy ? 'HEALTHY' : 'FAULT'}
                {latest ? ` · telemetry ${new Date(latest.timestamp).toLocaleTimeString()}` : ' · no telemetry received'}
              </span>
            </div>
          );
        })}
      </div>
      {espAlerts.length > 0 && (
        <div className="event-list">
          {espAlerts.map((alert, index) => (
            <div className="event" key={`${alert.timestamp}-${index}`}>
              <div className="event-icon red"><AlertTriangle size={15} /></div>
              <div className="event-copy">
                <b>{alert.severity}</b>
                <p>{alert.message}</p>
                <time>{new Date(alert.timestamp).toLocaleTimeString()}</time>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 6: Render panels in `web/src/App.tsx`**

Replace the placeholder `<section className="zone-grid">…</section>` block with:

```tsx
      <SceneHeader />
      <section className="zone-grid">
        {feed.state
          ? ZONES.map((zoneId) => (
              <ZonePanel key={zoneId} zone={feed.state!.zones[zoneId]} label={`ZONE ${zoneId.slice(-1)}`} />
            ))
          : ZONES.map((zoneId) => (
              <div className="panel" key={zoneId}><div className="empty">Awaiting state…</div></div>
            ))}
      </section>
      <TrainPanel state={feed.state} />
```

Add the imports at the top of `App.tsx`:

```tsx
import SceneHeader from './components/SceneHeader';
import ZonePanel from './components/ZonePanel';
import TrainPanel from './components/TrainPanel';
import Esp32Panel from './components/Esp32Panel';
import { ZONES } from './lib/types';
```

Render `<Esp32Panel />` later (Task 7 modifies the arrangement); for now also add it after `<TrainPanel …/>`:

```tsx
      <Esp32Panel />
```

- [ ] **Step 7: Append CSS for the new classes to `web/src/style.css`**

```css
.zone-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:16px}
.scene-zones{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:16px}
.scene-lane{position:relative;min-height:200px;background:#0b1b2a;border:1px solid #1b3547;border-radius:17px;overflow:hidden}
.scene-lane .signal{position:absolute;right:20px;top:20px}
.signal-stack{display:flex;flex-direction:column;gap:6px;padding:8px;background:#0c1a26;border:1px solid #22404f;border-radius:10px}
.signal-stack i{width:12px;height:12px;border-radius:50%;background:#1d3340;display:block}
.signal-stack i.on.red,.signal-stack i.red{background:#ff5b5b;box-shadow:0 0 8px #ff5b5b}
.signal-stack i.on.amber{background:#f5c46c;box-shadow:0 0 8px #f5c46c}
.signal-stack i.on.green{background:#6ce0ba;box-shadow:0 0 8px #6ce0ba}
.zone-rows{display:flex;flex-direction:column;gap:10px;margin-top:14px}
.zone-row{display:flex;justify-content:space-between;align-items:center;font:12px 'DM Mono',monospace;color:#9db3c6}
.zr-label{display:flex;align-items:center;gap:7px}
.zr-value{font-weight:500}
.zr-value.green,.metric-value.green{color:#6ce0ba}
.zr-value.amber{color:#f5c46c}
.zr-value.red,.metric-value.red{color:#ff7b7b}
.metric-grid.inner{margin:0;padding-top:12px}
.metric-grid.inner .metric{background:transparent;border:none}
.ghost{background:transparent;border:1px solid #294451;color:#c3d4e2;padding:7px 11px;border-radius:8px;display:inline-flex;align-items:center;gap:7px}
.user-chip{font:11px 'DM Mono',monospace;color:#9db3c6;letter-spacing:.4px}
.login-wrap{min-height:100vh;display:grid;place-items:center;padding:24px}
.login-card{width:min(430px,100%);background:#0b1b2a;border:1px solid #1b3547;border-radius:17px;padding:30px;display:flex;flex-direction:column;gap:14px}
.login-sub{color:#8ba2b7;font-size:13px;margin:0}
.login-field{display:flex;flex-direction:column;gap:6px;font:500 11px 'DM Mono',monospace;color:#7692a8}
.login-field input{background:#0c1a26;border:1px solid #22404f;border-radius:8px;padding:11px;color:#e9f0f8;font:14px 'DM Sans',sans-serif}
.login-field input:focus{outline:none;border-color:#2f6f7f}
.login-error{background:#2a1414;border:1px solid #5b2a2a;color:#ff9b9b;padding:10px 12px;border-radius:8px;font-size:12px}
.login-hint{color:#5f7d92;font-size:11px;text-align:center;margin:0}
```

- [ ] **Step 8: Build**

Run: `cd web && npm run build`
Expected: PASS.

- [ ] **Step 9: Manual verification**

With the stack up and Godot/another publisher optional:
1. Login as `operator`. Both zone panels render; zone1 and zone2 show `NORMAL`/`GREEN` (or the backend's current state).
2. Run a backend simulation event: `curl -X POST localhost:3001/api/event -H 'Content-Type: application/json' -d '{"type":"WILDLIFE_DETECTED","zone":"zone1"}'` → zone1 panel turns RED/`HAZARD`, zone2 shows YELLOW; the scene lane shows the wildlife marker.
3. `curl -X POST localhost:3001/api/event -d '{"type":"SIMULATION_TELEMETRY","zone":"zone1","speedKmh":37,"trainPresent":true}' -H 'Content-Type: application/json'` → Train panel speed updates.
4. ESP32 panel shows per-zone sensor health and `no telemetry received` (no publisher in Stage B) — never "healthy" when unknown.

- [ ] **Step 10: Commit**

```bash
git add web/src/components/Metric.tsx web/src/components/SceneHeader.tsx web/src/components/ZonePanel.tsx web/src/components/TrainPanel.tsx web/src/components/Esp32Panel.tsx web/src/App.tsx web/src/style.css
git commit -m "feat(web): add two-zone, train, and ESP32 monitoring panels"
```

---

### Task 7: Feeds (`EventFeed`, `AlertFeed`, `AuditFeed`) and layout

**Files:**
- Create: `web/src/components/EventFeed.tsx`
- Create: `web/src/components/AlertFeed.tsx`
- Create: `web/src/components/AuditFeed.tsx`
- Modify: `web/src/App.tsx` (render feeds; add ControlPanel placeholder)
- Modify: `web/src/style.css` (append feed/audit classes)

**Interfaces:**
- Consumes: `useApp` (Task 4), types (Task 1).
- Produces: default-exported `EventFeed`, `AlertFeed`, `AuditFeed({ rows })`.

- [ ] **Step 1: Create `web/src/components/EventFeed.tsx`**

```tsx
import { Activity, AlertTriangle } from 'lucide-react';
import { useApp } from '../context/AppContext';

export default function EventFeed() {
  const { feed } = useApp();
  const events = feed.events.slice(0, 8);
  return (
    <div className="panel">
      <div className="panel-head">
        <div><div className="eyebrow">EVENT STREAM</div><h3>Recent system events</h3></div>
        <Activity size={19} />
      </div>
      <div className="event-list">
        {events.length === 0 ? (
          <div className="empty">No events yet. Inject a scenario to begin.</div>
        ) : (
          events.map((event) => {
            const danger = event.result === 'REJECTED' || event.type.includes('FAULT');
            return (
              <div className="event" key={event.id}>
                <div className={`event-icon ${danger ? 'red' : ''}`}><AlertTriangle size={15} /></div>
                <div className="event-copy">
                  <b>{event.type.replaceAll('_', ' ')}</b>
                  <p>{event.message || event.zone || event.source || 'Simulation event'}</p>
                  <time>{new Date(event.time).toLocaleTimeString()}</time>
                </div>
                <span className="event-source">{event.source || 'SYSTEM'}</span>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Create `web/src/components/AlertFeed.tsx`**

```tsx
import { AlertTriangle, Bell } from 'lucide-react';
import { useApp } from '../context/AppContext';

export default function AlertFeed() {
  const { feed } = useApp();
  const alerts = feed.alerts.slice(0, 8);
  return (
    <div className="panel">
      <div className="panel-head">
        <div><div className="eyebrow">ALERTS</div><h3>Safety alerts</h3></div>
        <Bell size={19} />
      </div>
      <div className="event-list">
        {alerts.length === 0 ? (
          <div className="empty">No alerts.</div>
        ) : (
          alerts.map((alert, index) => (
            <div className={`event ${alert.severity === 'HIGH' ? 'alert-high' : ''}`} key={`${alert.timestamp}-${index}`}>
              <div className="event-icon red"><AlertTriangle size={15} /></div>
              <div className="event-copy">
                <b>{alert.severity} · {alert.source}</b>
                <p>{alert.message}</p>
                <time>{new Date(alert.timestamp).toLocaleTimeString()}</time>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Create `web/src/components/AuditFeed.tsx`**

```tsx
import { ScrollText } from 'lucide-react';
import type { AuditRow } from '../lib/types';

export default function AuditFeed({ rows }: { rows: AuditRow[] }) {
  return (
    <div className="panel">
      <div className="panel-head">
        <div><div className="eyebrow">AUDIT / SECURITY</div><h3>Accepted &amp; rejected actions</h3></div>
        <ScrollText size={19} />
      </div>
      <div className="audit-list">
        {rows.length === 0 ? (
          <div className="empty">No audit records.</div>
        ) : (
          rows.slice(0, 40).map((row) => (
            <div className="audit-row" key={row.id}>
              <span className={`audit-result ${row.result === 'ACCEPTED' ? 'green' : row.result === 'INFO' ? '' : 'red'}`}>
                {row.result}
              </span>
              <span className="audit-action">{row.action}</span>
              <span className="audit-actor">{row.actor ?? '—'}{row.zone ? ` @ ${row.zone}` : ''}</span>
              <span className="audit-reason">{row.reason ?? ''}</span>
              <time>{new Date(row.time).toLocaleTimeString()}</time>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Render feeds and control placeholder in `web/src/App.tsx`**

Replace the `shell` body (after the `{feed.stale && …}` block) with:

```tsx
      <SceneHeader />
      <section className="zone-grid">
        {feed.state
          ? ZONES.map((zoneId) => (
              <ZonePanel key={zoneId} zone={feed.state!.zones[zoneId]} label={`ZONE ${zoneId.slice(-1)}`} />
            ))
          : ZONES.map((zoneId) => (
              <div className="panel" key={zoneId}><div className="empty">Awaiting state…</div></div>
            ))}
      </section>
      <TrainPanel state={feed.state} />
      <Esp32Panel />
      <section className="lower-grid">
        <div className="panel"><div className="eyebrow">SCENARIO CONTROL</div><div className="empty">Controls render here.</div></div>
        <EventFeed />
      </section>
      <section className="lower-grid">
        <AlertFeed />
        <div className="panel"><div className="empty">—</div></div>
      </section>
      {auth.user.role === 'admin' && <AuditFeed rows={audit} />}
      <footer>
        <span>MQTT bridge · REST API · Godot 4</span>
        <span className="disclaimer">EDUCATIONAL SIMULATION ONLY</span>
      </footer>
```

Add imports:

```tsx
import EventFeed from './components/EventFeed';
import AlertFeed from './components/AlertFeed';
import AuditFeed from './components/AuditFeed';
```

And read `audit` from context: change the destructure to `const { auth, feed, audit } = useApp();`.

- [ ] **Step 5: Append CSS to `web/src/style.css`**

```css
.audit-list{display:flex;flex-direction:column;gap:2px;margin-top:12px;max-height:420px;overflow:auto}
.audit-row{display:grid;grid-template-columns:86px 1fr 1.2fr 1.4fr 72px;gap:10px;align-items:center;font:11px 'DM Mono',monospace;color:#9db3c6;padding:8px 6px;border-bottom:1px solid #142a38}
.audit-result.green{color:#6ce0ba}
.audit-result.red{color:#ff7b7b}
.audit-action{color:#dbe7f2}
.audit-reason{color:#7692a8;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.audit-row time{color:#5f7d92;text-align:right}
.event.alert-high{border-left:3px solid #ff5b5b}
```

- [ ] **Step 6: Build**

Run: `cd web && npm run build`
Expected: PASS.

- [ ] **Step 7: Manual verification (feeds + admin audit)**

1. Login `operator`. Event feed updates as events occur (push, no polling). Alert feed populates when an ESP32 fault alert is published (or via `curl -X POST localhost:3001/api/event -d '{"type":"SENSOR_FAULT","zone":"zone1"}' -H 'Content-Type: application/json'` then an ESP32 alert path — alerts appear when the backend publishes `railway/alerts`).
2. Login `admin`. The audit panel appears; perform a control command (Task 8) or a `viewer`-style 403 (Task 8) and confirm rows appear within ~5 s with `ACCEPTED`/`REJECTED`/`FORBIDDEN`.
3. Login `viewer`. No audit panel.
4. Repeated identical broker events do not duplicate rows (id dedupe).

- [ ] **Step 8: Commit**

```bash
git add web/src/components/EventFeed.tsx web/src/components/AlertFeed.tsx web/src/components/AuditFeed.tsx web/src/App.tsx web/src/style.css
git commit -m "feat(web): add event, alert, and admin audit feeds"
```

---

### Task 8: Control panel (role-gated commands + per-zone speed)

**Files:**
- Create: `web/src/components/ControlPanel.tsx`
- Modify: `web/src/App.tsx` (render `<ControlPanel />` in the control slot)
- Modify: `web/src/style.css` (append classes)

**Interfaces:**
- Consumes: `useApp` (Task 4), `ZONES`/`COMMAND_TYPES`/types (Task 1).
- Produces: default-exported `ControlPanel` (renders `null` for `viewer`).

- [ ] **Step 1: Create `web/src/components/ControlPanel.tsx`**

```tsx
import { useState } from 'react';
import { RotateCcw, Zap } from 'lucide-react';
import { useApp } from '../context/AppContext';
import { COMMAND_TYPES, ZONES, type CommandType, type ZoneId } from '../lib/types';

const PRIMARY: CommandType[] = ['WILDLIFE_DETECTED', 'SENSOR_FAULT'];
const RECOVER: CommandType[] = ['WILDLIFE_CLEARED', 'SENSOR_RESTORED'];

export default function ControlPanel() {
  const { auth, actions, feed } = useApp();
  const [speeds, setSpeeds] = useState<Record<ZoneId, number>>({ zone1: 48, zone2: 48 });
  const [busy, setBusy] = useState(false);

  const role = auth.user?.role;
  if (role !== 'operator' && role !== 'admin') return null;

  async function run(zone: ZoneId, event: CommandType) {
    setBusy(true);
    try {
      await actions.issueCommand(zone, event);
    } catch {
      /* lastError surfaced by context */
    } finally {
      setBusy(false);
    }
  }

  async function applySpeed(zone: ZoneId) {
    setBusy(true);
    try {
      await actions.setSpeed(zone, speeds[zone]);
    } catch {
      /* lastError surfaced by context */
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="panel control-panel">
      <div className="panel-head">
        <div><div className="eyebrow">SCENARIO CONTROL</div><h3>Simulation controls</h3></div>
        <Zap size={19} />
      </div>
      {ZONES.map((zoneId) => {
        const zone = feed.state?.zones[zoneId];
        return (
          <div className="control-zone" key={zoneId}>
            <div className="control-zone-head">
              <b>{zoneId.toUpperCase()}</b>
              <span>{zone ? zone.status.replaceAll('_', ' ') : 'UNKNOWN'}</span>
            </div>
            <div className="button-row">
              {PRIMARY.map((event) => (
                <button className="secondary" key={event} disabled={busy} onClick={() => run(zoneId, event)}>
                  {event.replaceAll('_', ' ')}
                </button>
              ))}
            </div>
            <div className="button-row">
              {RECOVER.map((event) => (
                <button className="secondary" key={event} disabled={busy} onClick={() => run(zoneId, event)}>
                  {event.replaceAll('_', ' ')}
                </button>
              ))}
            </div>
            <div className="button-row">
              <button className="secondary" disabled={busy} onClick={() => run(zoneId, 'TRAIN_ENTERED_ZONE')}>
                Train entered
              </button>
              <button className="secondary" disabled={busy} onClick={() => run(zoneId, 'TRAIN_LEFT_ZONE')}>
                Train left
              </button>
            </div>
            <div className="slider-head">
              <label>Target speed · {zoneId}</label>
              <strong>{speeds[zoneId]} <small>km/h</small></strong>
            </div>
            <input
              type="range" min="0" max="80" step="4"
              value={speeds[zoneId]}
              onChange={(e) => setSpeeds((prev) => ({ ...prev, [zoneId]: Number(e.target.value) }))}
            />
            <button className="primary full" disabled={busy} onClick={() => applySpeed(zoneId)}>
              Apply target speed
            </button>
            <button className="reset" disabled={busy} onClick={() => run(zoneId, 'RESET')}>
              <RotateCcw size={15} /> Reset {zoneId} to normal
            </button>
          </div>
        );
      })}
    </div>
  );
}
```

- [ ] **Step 2: Render `<ControlPanel />` in `web/src/App.tsx`**

Replace the control placeholder:

```tsx
      <section className="lower-grid">
        <ControlPanel />
        <EventFeed />
      </section>
```

Add import:

```tsx
import ControlPanel from './components/ControlPanel';
```

- [ ] **Step 3: Append CSS to `web/src/style.css`**

```css
.control-zone{border-top:1px solid #142a38;padding-top:14px;margin-top:14px;display:flex;flex-direction:column;gap:10px}
.control-zone:first-of-type{border-top:none;padding-top:0}
.control-zone-head{display:flex;justify-content:space-between;font:12px 'DM Mono',monospace;color:#9db3c6}
.control-zone-head span{color:#5f7d92}
```

- [ ] **Step 4: Build**

Run: `cd web && npm run build`
Expected: PASS.

- [ ] **Step 5: Manual verification (role gating + command contract)**

1. Login `viewer` → no control panel at all.
2. Login `operator` → control panel renders. Click "WILDLIFE DETECTED" on ZONE 1 → zone1 turns RED/HAZARD, zone2 YELLOW; event feed shows the accepted event; Train panel updates speed path.
3. Click "Reset zone1 to normal" while hazard active → an inline error shows the 409 "transition rejected" reason (from `lastError`/context).
4. Click "Wildlife cleared", then reset → succeeds.
5. Move the ZONE 2 speed slider and apply → zone2 `targetSpeedKmh` updates in its panel (via MQTT state).
6. Login `admin` → audit feed records the accepted/rejected actions.

- [ ] **Step 6: Commit**

```bash
git add web/src/components/ControlPanel.tsx web/src/App.tsx web/src/style.css
git commit -m "feat(web): add role-gated control panel with per-zone commands and speed"
```

---

### Task 9: Broker ACL, layout polish, end-to-end acceptance

**Files:**
- Modify: `mosquitto/acl_file` (add telemetry read line for `dashboard`)
- Modify: `web/src/App.tsx` (final layout cleanup if needed)
- Modify: `web/src/style.css` (any final polish)

**Interfaces:**
- Consumes: everything above.
- Produces: the completed Stage B dashboard; no code interfaces.

- [ ] **Step 1: Add the ACL read line**

In `mosquitto/acl_file`, under `user dashboard`, append after `topic read railway/alerts`:

```
topic read railway/telemetry/esp32
```

The block becomes:

```
user dashboard
topic read railway/state
topic read railway/events
topic read railway/alerts
topic read railway/telemetry/esp32
```

- [ ] **Step 2: Restart the broker and confirm the ACL**

```bash
docker compose restart mqtt
docker compose exec mqtt cat /mosquitto/config/acl_file | tail -5
```

Expected: the four `topic read` lines under `user dashboard`, with the telemetry line present.

- [ ] **Step 3: Confirm the dashboard cannot publish to MQTT**

With `mqtt` available in `web/node_modules`, run a one-off publish as the `dashboard` user and confirm the broker denies it (connection closes / publish not delivered):

```bash
cd web && node -e "const mqtt=require('mqtt');const c=mqtt.connect('ws://localhost:9001',{username:'dashboard',password:'dashboard-dev-pass'});c.on('connect',()=>{console.log('connected (read-only)');c.publish('railway/commands/zone1',JSON.stringify({x:1}),{qos:0},()=>{c.end(true);})});c.on('error',(e)=>{console.log('denied:',e.message);process.exit(0)});c.on('close',()=>{console.log('closed');process.exit(0)});setTimeout(()=>process.exit(0),3000)"
```

Expected: the client connects but the broker closes the connection when it attempts to publish to a write-forbidden topic (ACL denial) — it does not successfully publish. Record the observed behavior as evidence.

- [ ] **Step 4: Run the full acceptance checklist**

The spec's §11 acceptance checklist must all pass. Perform it with broker + backend + `npm run dev` running, and capture results:

- [ ] `npm run build` passes.
- [ ] `viewer`/`operator`/`admin` each see the correct panels.
- [ ] Login failure (401) and expired-token (401 on a later call) return to the login screen.
- [ ] All four MQTT subscriptions work over WebSockets (state, events, alerts, telemetry/esp32).
- [ ] The dashboard cannot publish to MQTT (ACL grants it no write topic).
- [ ] The seven command types map to the exact backend envelope.
- [ ] Duplicate `event.id`s do not create duplicate rows.
- [ ] A stale REST state cannot overwrite newer live state (`updatedAt` rule).
- [ ] Per-zone targets stay consistent with the active train panel.
- [ ] Broker stop/start produces a visible OFFLINE → connected transition.
- [ ] Audit polling starts only for admins and stops on logout.
- [ ] Malformed MQTT payloads and missing telemetry are handled safely.

For "malformed payloads": publish a non-JSON message to `railway/events` from a permitted publisher (e.g. `backend` creds) and confirm the feed logs a warning and does not crash:

```bash
cd backend && node -e "const mqtt=require('mqtt');const c=mqtt.connect('mqtt://127.0.0.1:1883',{username:'backend',password:'backend-dev-pass'});c.on('connect',()=>{c.publish('railway/events','not-json');setTimeout(()=>c.end(true),500)})"
```

Expected: dashboard console shows `[feed] dropped malformed payload on railway/events`; UI unaffected.

- [ ] **Step 5: Fix any defects found, then re-run `npm run build`**

Run: `cd web && npm run build`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mosquitto/acl_file web/src/App.tsx web/src/style.css
git commit -m "feat(web): allow dashboard to read ESP32 telemetry over MQTT; finalize Stage B layout"
```

---

## Self-Review

**1. Spec coverage:**
- §2 login/logout, role-aware UI → Tasks 4, 5, 8. Live MQTT state/events/alerts/telemetry → Tasks 3, 4, 6, 7. Two-zone viz → Task 6. Train panel → Task 6. Control panel (per-zone commands + speed) → Task 8. Admin audit feed → Tasks 4, 7. ESP32 panel → Task 6. Connection/health → Tasks 4, 5.
- §4 ACL change → Task 9.
- §5 config → Task 1.
- §6 module layout/interfaces → Tasks 1–4.
- §7 contracts → Tasks 2, 3 (with `parseState` validation).
- §8 UI/UX → Tasks 5–8.
- §9 behavior (command flow, reconciliation, health poll, audit poll, event dedupe) → Tasks 4, 6.
- §10 error handling → Task 4 (`handleError` 401/403/400/409), Task 3 (malformed), Task 6 (telemetry empty state), Task 5 (stale banner).
- §11 verification → each task's manual step + Task 9 full checklist.
- §12 risks → Task 3 (browser entry check), Task 9 (publish denial).

**2. Placeholder scan:** No `TBD`/`TODO`/"implement later". All code steps contain complete, compilable code (the CSS block uses a real `#5f7d92` value).

**3. Type consistency:** `createFeed`/`FeedOptions`/`Feed` names match Tasks 3→4. `useTwinFeed` returns `applyRestState`/`applyRestEvents`, consumed in Task 4. `api.*` signatures (Task 2) match Task 4 call sites. `Metric` props `{icon,label,value,sub,tone?}` match Task 6 uses. `ZonePanel({zone,label})`, `TrainPanel({state})`, `AuditFeed({rows})` match their render sites. Types (`TwinState`, `Zone`, `EventRow`, `AlertRow`, `TelemetryRow`, `AuditRow`, `User`, `CommandEnvelope`, `CommandType`, `ZoneId`, `FeedStatus`) are defined once in Task 1 and reused.

**Deviation note:** no unit-test tasks are included because the repo has no web test runner and the approved spec fixes the gate as `npm run build` + manual checklist (Global Constraints). Pure logic (`parseState`, reconciliation, `ApiError` normalization) is isolated in `lib/` for future testability.
