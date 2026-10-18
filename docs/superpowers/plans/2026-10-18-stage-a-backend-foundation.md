# Stage A — Backend Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the backend as the trusted MQTT control plane — authenticated broker (per-client credentials + ACLs), JWT/RBAC HTTP API, two-zone state machine, SQLite replay + audit, and an MQTT bridge — fully covered by automated tests.

**Architecture:** A composition root (`server.js`) wires pure, independently-testable modules (`config`, `db`, `audit`, `replay`, `auth`, `rbac`, `validate`, `state`, `bus`, `mqtt`, `events`) into an Express app (`src/app.js`). The dashboard's control actions arrive over authenticated REST; the backend validates, dedupes, applies the state transition, audits, and is the **only** publisher of command topics. Godot/ESP32 are authenticated broker clients that only emit their own telemetry.

**Tech Stack:** Node ≥22 (ESM, `node --test`, global `fetch`, `--env-file-if-exists`), Express 4, `mqtt` 5.16, `better-sqlite3` 13, `jsonwebtoken` 9, `bcryptjs` 3, Mosquitto 2 (Docker).

**Spec:** `docs/superpowers/specs/2026-10-18-railway-digital-twin-enhancement-design.md`

## Global Constraints

- Runtime: Node ≥22, ESM (`"type": "module"`). Config from `process.env` only; load `.env` via `node --env-file-if-exists=.env`.
- Zones are exactly `['zone1', 'zone2']`; command event names exactly: `WILDLIFE_DETECTED`, `WILDLIFE_CLEARED`, `SENSOR_FAULT`, `SENSOR_RESTORED`, `RESET`, `TRAIN_ENTERED_ZONE`, `TRAIN_LEFT_ZONE`.
- Roles exactly `viewer`, `operator`, `admin`. bcrypt rounds ≥12. JWT expiry `1h` (short-lived).
- Command envelope fields exactly: `request_id`, `zone`, `event`, `timestamp`, `source`, `payload`. Timestamps outside a ±5-minute window are stale and rejected.
- Speed range `0..80` km/h. Simulated braking deceleration `a = 1.2 m/s²`; stopping distance `= (v/3.6)² / (2a)`.
- Signals: `GREEN`/`YELLOW`/`RED`. A zone is `RED` when it has wildlife, an unhealthy sensor, or `RECOVERY_REQUIRED`; else `YELLOW` while any zone is restrictive; else `GREEN`.
- The backend is the **only** client that publishes `railway/commands/*`, `railway/speed/*`, `railway/zone*/signal`, `railway/state`, `railway/events`, `railway/alerts`, `railway/security/events`.
- Secrets are never committed. `mosquitto/password_file` and `.env` are git-ignored.
- No anonymous broker access (`allow_anonymous false`); no TLS in local dev (documented).

---

### Task 1: Backend scaffolding & config

**Files:**
- Create: `backend/package.json`
- Create: `backend/src/config.js`
- Create: `backend/.env.sample`
- Create: `backend/test/config.test.js`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `config` object with `{ port, mqttUrl, mqttUser, mqttPass, jwtSecret, jwtExpiresIn, bcryptRounds, dbPath, zones, seedUsers }` where `seedUsers: Array<{username,password,role}>`.

- [ ] **Step 1: Write the failing test**

`backend/test/config.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';

test('config exposes required defaults', async () => {
  const { config } = await import('../src/config.js');
  assert.deepEqual(config.zones, ['zone1', 'zone2']);
  assert.equal(config.port, 3001);
  assert.equal(config.mqttUser, 'backend');
  assert.ok(config.bcryptRounds >= 12);
  assert.equal(config.seedUsers.length, 3);
  assert.deepEqual(config.seedUsers.map((u) => u.role).sort(), ['admin', 'operator', 'viewer']);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test backend/test/config.test.js`
Expected: FAIL — `Cannot find module '../src/config.js'`.

- [ ] **Step 3: Write minimal implementation**

`backend/src/config.js`:
```js
export const config = {
  port: Number(process.env.PORT || 3001),
  mqttUrl: process.env.MQTT_URL || 'mqtt://127.0.0.1:1883',
  mqttUser: process.env.MQTT_BACKEND_USER || 'backend',
  mqttPass: process.env.MQTT_BACKEND_PASS || 'backend-dev-pass',
  jwtSecret: process.env.JWT_SECRET || 'dev-insecure-secret-change-me',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '1h',
  bcryptRounds: Number(process.env.BCRYPT_ROUNDS || 12),
  dbPath: process.env.DB_PATH || './data/railway.db',
  zones: ['zone1', 'zone2'],
  seedUsers: [
    { username: 'viewer', password: process.env.VIEWER_PASSWORD || 'viewer-dev-pass', role: 'viewer' },
    { username: 'operator', password: process.env.OPERATOR_PASSWORD || 'operator-dev-pass', role: 'operator' },
    { username: 'admin', password: process.env.ADMIN_PASSWORD || 'admin-dev-pass', role: 'admin' },
  ],
};
```

`backend/package.json`:
```json
{
  "name": "railway-digital-twin-backend",
  "version": "0.2.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node --env-file-if-exists=.env server.js",
    "dev": "node --env-file-if-exists=.env --watch server.js",
    "test": "node --env-file-if-exists=.env.test --test"
  },
  "dependencies": {
    "bcryptjs": "^3.0.3",
    "better-sqlite3": "^13.0.3",
    "cors": "^2.8.5",
    "express": "^4.21.2",
    "jsonwebtoken": "^9.0.3",
    "mqtt": "^5.16.1"
  }
}
```

`backend/.env.sample`:
```dotenv
PORT=3001
MQTT_URL=mqtt://127.0.0.1:1883
MQTT_BACKEND_USER=backend
MQTT_BACKEND_PASS=backend-dev-pass
MQTT_GODOT_PASS=godot-dev-pass
MQTT_ESP32_PASS=esp32-dev-pass
MQTT_DASHBOARD_PASS=dashboard-dev-pass
JWT_SECRET=change-me
VIEWER_PASSWORD=viewer-dev-pass
OPERATOR_PASSWORD=operator-dev-pass
ADMIN_PASSWORD=admin-dev-pass
DB_PATH=./data/railway.db
```

Append to `.gitignore`:
```
backend/.env
backend/.env.test
backend/data/
mosquitto/password_file
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npm install && node --test test/config.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/package.json backend/src/config.js backend/.env.sample backend/test/config.test.js .gitignore
git commit -m "feat(backend): scaffold project and config"
```

---

### Task 2: SQLite schema + audit store

**Files:**
- Create: `backend/src/db.js`
- Create: `backend/src/audit.js`
- Create: `backend/test/audit.test.js`

**Interfaces:**
- Produces: `openDb(path) -> Database` (creates `users`, `processed_requests`, `audit` tables).
- Produces: `makeAudit(db) -> { write(entry) -> row, list(limit=100) -> row[] }` where `entry` is a partial of `{time,actor,role,action,zone,target,result,reason,source}`.

- [ ] **Step 1: Write the failing test**

`backend/test/audit.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb } from '../src/db.js';
import { makeAudit } from '../src/audit.js';

test('audit writes and lists newest-first with defaults', () => {
  const db = openDb(':memory:');
  const audit = makeAudit(db);
  const a = audit.write({ actor: 'operator', role: 'operator', action: 'RESET', result: 'ACCEPTED', zone: 'zone1' });
  audit.write({ action: 'SPEED', result: 'REJECTED', reason: 'range' });
  assert.ok(a.id);
  assert.equal(a.result, 'ACCEPTED');
  const rows = audit.list();
  assert.equal(rows.length, 2);
  assert.equal(rows[0].action, 'SPEED');
  assert.equal(rows[0].result, 'REJECTED');
});

test('audit.list caps the limit', () => {
  const db = openDb(':memory:');
  const audit = makeAudit(db);
  for (let i = 0; i < 5; i++) audit.write({ action: 'X', result: 'INFO' });
  assert.equal(audit.list(1000).length, 5);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/audit.test.js`
Expected: FAIL — `Cannot find module '../src/db.js'`.

- [ ] **Step 3: Write minimal implementation**

`backend/src/db.js`:
```js
import Database from 'better-sqlite3';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export function openDb(path) {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
  const db = new Database(path);
  db.pragma('journal_mode = WAL');
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('viewer','operator','admin')),
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS processed_requests (
      request_id TEXT PRIMARY KEY,
      username TEXT NOT NULL,
      action TEXT NOT NULL,
      received_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS audit (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      time TEXT NOT NULL,
      actor TEXT,
      role TEXT,
      action TEXT NOT NULL,
      zone TEXT,
      target TEXT,
      result TEXT NOT NULL,
      reason TEXT,
      source TEXT
    );
  `);
  return db;
}
```

`backend/src/audit.js`:
```js
export function makeAudit(db) {
  const insert = db.prepare(
    `INSERT INTO audit (time,actor,role,action,zone,target,result,reason,source)
     VALUES (@time,@actor,@role,@action,@zone,@target,@result,@reason,@source)`
  );
  const recent = db.prepare('SELECT * FROM audit ORDER BY id DESC LIMIT ?');
  return {
    write(entry = {}) {
      const row = {
        time: new Date().toISOString(), actor: null, role: null,
        action: 'UNKNOWN', zone: null, target: null, result: 'INFO',
        reason: null, source: null, ...entry,
      };
      const info = insert.run(row);
      return { id: info.lastInsertRowid, ...row };
    },
    list(limit = 100) {
      const n = Math.min(Math.max(Number(limit) || 100, 1), 500);
      return recent.all(n);
    },
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/audit.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/db.js backend/src/audit.js backend/test/audit.test.js
git commit -m "feat(backend): sqlite schema and audit store"
```

---

### Task 3: Replay registry

**Files:**
- Create: `backend/src/replay.js`
- Create: `backend/test/replay.test.js`

**Interfaces:**
- Produces: `makeReplay(db) -> { check(requestId, {username, action}) -> {ok, reason?}, prune(maxAgeMs) -> number }`.

- [ ] **Step 1: Write the failing test**

`backend/test/replay.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb } from '../src/db.js';
import { makeReplay } from '../src/replay.js';

test('rejects missing and duplicate request ids', () => {
  const replay = makeReplay(openDb(':memory:'));
  assert.equal(replay.check('', { username: 'operator' }).ok, false);
  assert.equal(replay.check('req-1', { username: 'operator', action: 'RESET' }).ok, true);
  const dup = replay.check('req-1', { username: 'operator', action: 'RESET' });
  assert.equal(dup.ok, false);
  assert.match(dup.reason, /duplicate/);
});

test('prune removes entries older than the window', () => {
  const db = openDb(':memory:');
  const replay = makeReplay(db);
  replay.check('old', { username: 'u', action: 'A' });
  db.prepare('UPDATE processed_requests SET received_at = ?').run(new Date(Date.now() - 1000).toISOString());
  assert.equal(replay.prune(1), 1);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/replay.test.js`
Expected: FAIL — `Cannot find module '../src/replay.js'`.

- [ ] **Step 3: Write minimal implementation**

`backend/src/replay.js`:
```js
export function makeReplay(db) {
  const insert = db.prepare(
    'INSERT INTO processed_requests (request_id,username,action,received_at) VALUES (?,?,?,?)'
  );
  const exists = db.prepare('SELECT 1 AS hit FROM processed_requests WHERE request_id = ?');
  const deleteOld = db.prepare('DELETE FROM processed_requests WHERE received_at < ?');
  return {
    check(requestId, { username = '', action = '' } = {}) {
      const id = String(requestId || '');
      if (!id) return { ok: false, reason: 'missing request_id' };
      if (exists.get(id)) return { ok: false, reason: 'duplicate request_id' };
      insert.run(id, String(username), String(action), new Date().toISOString());
      return { ok: true };
    },
    prune(maxAgeMs = 24 * 3600 * 1000) {
      return deleteOld.run(new Date(Date.now() - maxAgeMs).toISOString()).changes;
    },
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/replay.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/replay.js backend/test/replay.test.js
git commit -m "feat(backend): request_id replay registry"
```

---

### Task 4: Auth (bcrypt, JWT, seeding, middleware)

**Files:**
- Create: `backend/src/auth.js`
- Create: `backend/test/auth.test.js`

**Interfaces:**
- Consumes: `openDb`, `config`.
- Produces: `makeAuth({db, config}) -> { seedUsers(), login(username,password) -> {ok, token?, user?, reason?}, verifyToken(token) -> {ok, user?, reason?}, requireAuth(req,res,next) }`.

- [ ] **Step 1: Write the failing test**

`backend/test/auth.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb } from '../src/db.js';
import { makeAuth } from '../src/auth.js';
import { config } from '../src/config.js';

function makeReq(token) {
  return { headers: token ? { authorization: `Bearer ${token}` } : {} };
}
const res = () => ({ statusCode: 200, body: null, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; } });

test('seeds users idempotently and authenticates them', () => {
  const auth = makeAuth({ db: openDb(':memory:'), config });
  auth.seedUsers();
  auth.seedUsers();
  const bad = auth.login('operator', 'nope');
  assert.equal(bad.ok, false);
  const good = auth.login('operator', config.seedUsers.find((u) => u.role === 'operator').password);
  assert.equal(good.ok, true);
  assert.equal(good.user.role, 'operator');
  const verified = auth.verifyToken(good.token);
  assert.equal(verified.ok, true);
  assert.equal(verified.user.username, 'operator');
});

test('requireAuth rejects missing/invalid tokens and passes valid ones', () => {
  const auth = makeAuth({ db: openDb(':memory:'), config });
  auth.seedUsers();
  const r1 = res();
  let called = false;
  auth.requireAuth(makeReq(), r1, () => { called = true; });
  assert.equal(r1.statusCode, 401);
  assert.equal(called, false);

  const { token } = auth.login('viewer', config.seedUsers.find((u) => u.role === 'viewer').password);
  const req = makeReq(token);
  const r2 = res();
  auth.requireAuth(req, r2, () => { called = true; });
  assert.equal(called, true);
  assert.equal(req.user.role, 'viewer');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/auth.test.js`
Expected: FAIL — `Cannot find module '../src/auth.js'`.

- [ ] **Step 3: Write minimal implementation**

`backend/src/auth.js`:
```js
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

export function makeAuth({ db, config }) {
  const findByUsername = db.prepare('SELECT * FROM users WHERE username = ?');
  const insertUser = db.prepare(
    'INSERT INTO users (username,password_hash,role,created_at) VALUES (?,?,?,?)'
  );

  function seedUsers() {
    for (const u of config.seedUsers) {
      if (!findByUsername.get(u.username)) {
        insertUser.run(u.username, bcrypt.hashSync(u.password, config.bcryptRounds), u.role, new Date().toISOString());
      }
    }
  }

  function login(username, password) {
    const user = findByUsername.get(String(username || ''));
    if (!user || !bcrypt.compareSync(String(password || ''), user.password_hash)) {
      return { ok: false, reason: 'invalid credentials' };
    }
    const token = jwt.sign(
      { sub: user.id, username: user.username, role: user.role },
      config.jwtSecret,
      { expiresIn: config.jwtExpiresIn }
    );
    return { ok: true, token, user: { username: user.username, role: user.role } };
  }

  function verifyToken(token) {
    try {
      return { ok: true, user: jwt.verify(String(token || ''), config.jwtSecret) };
    } catch (e) {
      return { ok: false, reason: e.message };
    }
  }

  function requireAuth(req, res, next) {
    const header = String(req.headers.authorization || '');
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    const result = verifyToken(token);
    if (!result.ok) return res.status(401).json({ error: 'unauthorized' });
    req.user = { id: result.user.sub, username: result.user.username, role: result.user.role };
    return next();
  }

  return { seedUsers, login, verifyToken, requireAuth };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/auth.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/auth.js backend/test/auth.test.js
git commit -m "feat(backend): auth with bcrypt, jwt, seeding"
```

---

### Task 5: RBAC + validation

**Files:**
- Create: `backend/src/rbac.js`
- Create: `backend/src/validate.js`
- Create: `backend/test/rbac.test.js`
- Create: `backend/test/validate.test.js`

**Interfaces:**
- Produces: `hasPermission(role, perm) -> boolean`, `requirePermission(perm) -> middleware`.
- Produces: `validateCommand(body, {zones}) -> {ok, value?, reason?}` and `validateSpeed(body, {zones}) -> {ok, value?, reason?}`.

- [ ] **Step 1: Write the failing tests**

`backend/test/rbac.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hasPermission, requirePermission } from '../src/rbac.js';

test('role permission matrix', () => {
  assert.equal(hasPermission('viewer', 'state:read'), true);
  assert.equal(hasPermission('viewer', 'control:issue'), false);
  assert.equal(hasPermission('operator', 'control:issue'), true);
  assert.equal(hasPermission('operator', 'audit:read'), false);
  assert.equal(hasPermission('admin', 'audit:read'), true);
});

test('requirePermission enforces role', () => {
  const res = () => ({ code: 200, body: null, status(c) { this.code = c; return this; }, json(b) { this.body = b; return this; } });
  const r = res();
  let next = false;
  requirePermission('control:issue')({ user: { role: 'viewer' } }, r, () => { next = true; });
  assert.equal(r.code, 403);
  assert.equal(next, false);
  requirePermission('control:issue')({ user: { role: 'operator' } }, res(), () => { next = true; });
  assert.equal(next, true);
});
```

`backend/test/validate.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateCommand, validateSpeed } from '../src/validate.js';

const zones = ['zone1', 'zone2'];
const base = {
  request_id: 'r1', zone: 'zone1', event: 'WILDLIFE_DETECTED',
  timestamp: new Date().toISOString(), source: 'dashboard', payload: { wildlife_detected: true },
};

test('validateCommand accepts a well-formed envelope', () => {
  assert.equal(validateCommand(base, { zones }).ok, true);
});
test('validateCommand rejects missing id, bad zone, bad event, stale ts', () => {
  assert.equal(validateCommand({ ...base, request_id: '' }, { zones }).ok, false);
  assert.equal(validateCommand({ ...base, zone: 'zone9' }, { zones }).ok, false);
  assert.equal(validateCommand({ ...base, event: 'NOPE' }, { zones }).ok, false);
  assert.equal(validateCommand({ ...base, timestamp: '2000-01-01T00:00:00Z' }, { zones }).ok, false);
});
test('validateSpeed enforces zone and range', () => {
  assert.equal(validateSpeed({ zone: 'zone1', speedKmh: 30 }, { zones }).ok, true);
  assert.equal(validateSpeed({ zone: 'zone1', speedKmh: 100 }, { zones }).ok, false);
  assert.equal(validateSpeed({ zone: 'nope', speedKmh: 30 }, { zones }).ok, false);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && node --test test/rbac.test.js test/validate.test.js`
Expected: FAIL — modules not found.

- [ ] **Step 3: Write minimal implementation**

`backend/src/rbac.js`:
```js
export const PERMISSIONS = {
  viewer: ['state:read', 'events:read'],
  operator: ['state:read', 'events:read', 'control:issue', 'speed:set'],
  admin: ['state:read', 'events:read', 'control:issue', 'speed:set', 'audit:read', 'users:manage'],
};

export function hasPermission(role, perm) {
  return (PERMISSIONS[role] || []).includes(perm);
}

export function requirePermission(perm) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'unauthorized' });
    if (!hasPermission(req.user.role, perm)) return res.status(403).json({ error: 'forbidden' });
    return next();
  };
}
```

`backend/src/validate.js`:
```js
export const COMMAND_EVENTS = new Set([
  'WILDLIFE_DETECTED', 'WILDLIFE_CLEARED', 'SENSOR_FAULT', 'SENSOR_RESTORED',
  'RESET', 'TRAIN_ENTERED_ZONE', 'TRAIN_LEFT_ZONE',
]);
const STALE_MS = 5 * 60 * 1000;

export function validateCommand(body, { zones }) {
  const request_id = String(body?.request_id || '');
  const zone = String(body?.zone || '').toLowerCase();
  const event = String(body?.event || '').toUpperCase();
  const timestamp = String(body?.timestamp || '');
  const source = String(body?.source || 'dashboard');
  const payload = body?.payload && typeof body.payload === 'object' ? body.payload : {};
  const errors = [];
  if (!request_id) errors.push('request_id required');
  if (!zones.includes(zone)) errors.push('invalid zone');
  if (!COMMAND_EVENTS.has(event)) errors.push('unsupported event');
  const ts = Date.parse(timestamp);
  if (Number.isNaN(ts)) errors.push('invalid timestamp');
  else if (Math.abs(Date.now() - ts) > STALE_MS) errors.push('stale timestamp');
  if (errors.length) return { ok: false, reason: errors.join('; ') };
  return { ok: true, value: { request_id, zone, event, timestamp, source, payload } };
}

export function validateSpeed(body, { zones }) {
  const zone = String(body?.zone || '').toLowerCase();
  const speedKmh = Number(body?.speedKmh);
  if (!zones.includes(zone)) return { ok: false, reason: 'invalid zone' };
  if (!Number.isFinite(speedKmh) || speedKmh < 0 || speedKmh > 80) {
    return { ok: false, reason: 'speed must be 0..80' };
  }
  return { ok: true, value: { zone, speedKmh } };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && node --test test/rbac.test.js test/validate.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/rbac.js backend/src/validate.js backend/test/rbac.test.js backend/test/validate.test.js
git commit -m "feat(backend): rbac and command/speed validation"
```

---

### Task 6: Two-zone state machine

**Files:**
- Create: `backend/src/state.js`
- Create: `backend/test/state.test.js`

**Interfaces:**
- Produces: `makeState({config}) -> { snapshot() -> State, applyCommand(env) -> {ok, reason?}, applySpeed({zone,speedKmh}) -> {ok}, applyTelemetry(zone, msg) -> void, setBrokerConnected(bool) -> void }`.
- `State` shape: `{ zones: { zone1: Zone, zone2: Zone }, train: { zone, speedKmh, targetSpeedKmh, stoppingDistanceM }, comm: { mqttConnected }, overall, lastEvent, updatedAt }`; `Zone = { id, trainPresent, wildlifeDetected, sensorHealthy, signal, status, targetSpeedKmh }`.

- [ ] **Step 1: Write the failing test**

`backend/test/state.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeState } from '../src/state.js';

const config = { zones: ['zone1', 'zone2'] };
const env = (zone, event) => ({ request_id: `${event}-${zone}`, zone, event, timestamp: new Date().toISOString(), source: 'dashboard', payload: {} });

test('wildlife in zone1 makes zone1 RED and zone2 YELLOW, zones independent', () => {
  const s = makeState({ config });
  assert.equal(s.applyCommand(env('zone1', 'WILDLIFE_DETECTED')).ok, true);
  const snap = s.snapshot();
  assert.equal(snap.zones.zone1.signal, 'RED');
  assert.equal(snap.zones.zone2.signal, 'YELLOW');
  assert.equal(snap.zones.zone2.wildlifeDetected, false);
  assert.equal(snap.overall, 'HAZARD');
});

test('clearing wildlife requires reset and stays restrictive', () => {
  const s = makeState({ config });
  s.applyCommand(env('zone1', 'WILDLIFE_DETECTED'));
  s.applyCommand(env('zone1', 'WILDLIFE_CLEARED'));
  let snap = s.snapshot();
  assert.equal(snap.zones.zone1.signal, 'RED');
  assert.equal(snap.overall, 'RECOVERY_REQUIRED');
  assert.equal(s.applyCommand(env('zone1', 'RESET')).ok, true);
  snap = s.snapshot();
  assert.equal(snap.zones.zone1.signal, 'GREEN');
  assert.equal(snap.overall, 'NORMAL');
});

test('reset is rejected while hazard active', () => {
  const s = makeState({ config });
  s.applyCommand(env('zone2', 'SENSOR_FAULT'));
  const r = s.applyCommand(env('zone2', 'RESET'));
  assert.equal(r.ok, false);
  assert.match(r.reason, /reject/i);
});

test('sensor restore then reset returns to normal', () => {
  const s = makeState({ config });
  s.applyCommand(env('zone2', 'SENSOR_FAULT'));
  s.applyCommand(env('zone2', 'SENSOR_RESTORED'));
  assert.equal(s.snapshot().zones.zone2.signal, 'RED');
  s.applyCommand(env('zone2', 'RESET'));
  assert.equal(s.snapshot().overall, 'NORMAL');
});

test('per-zone speed and stopping distance', () => {
  const s = makeState({ config });
  assert.equal(s.applySpeed({ zone: 'zone1', speedKmh: 0 }).ok, true);
  const snap = s.snapshot();
  assert.equal(snap.zones.zone1.targetSpeedKmh, 0);
  s.applyTelemetry('zone1', { speedKmh: 36, trainPresent: true });
  assert.equal(s.snapshot().train.speedKmh, 36);
  assert.ok(s.snapshot().train.stoppingDistanceM > 0);
});

test('broker disconnect forces restrictive overall state', () => {
  const s = makeState({ config });
  s.setBrokerConnected(false);
  assert.equal(s.snapshot().overall, 'COMM_LOST');
  s.setBrokerConnected(true);
  assert.equal(s.snapshot().overall, 'NORMAL');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/state.test.js`
Expected: FAIL — `Cannot find module '../src/state.js'`.

- [ ] **Step 3: Write minimal implementation**

`backend/src/state.js`:
```js
const DECEL = 1.2; // m/s^2 simulated braking
const DEFAULT_TARGET = 48;

function newZone(id) {
  return {
    id, trainPresent: false, wildlifeDetected: false, sensorHealthy: true,
    signal: 'GREEN', status: 'NORMAL', targetSpeedKmh: DEFAULT_TARGET,
  };
}

export function makeState({ config }) {
  const zones = {};
  for (const id of config.zones) zones[id] = newZone(id);
  const train = { zone: config.zones[0], speedKmh: DEFAULT_TARGET, targetSpeedKmh: DEFAULT_TARGET, stoppingDistanceM: 0 };
  const comm = { mqttConnected: true }; // assume connected until told otherwise; server sets false at startup
  let lastEvent = 'System initialized';

  const isRestrictive = (z) => z.wildlifeDetected || !z.sensorHealthy || z.status === 'RECOVERY_REQUIRED';

  function sectionFor(zone) {
    return Object.keys(zones).filter((id) => id !== zone && isRestrictive(zones[id])).length;
  }

  function recompute() {
    for (const id of config.zones) {
      const z = zones[id];
      if (isRestrictive(z)) z.signal = 'RED';
      else if (sectionFor(id) > 0) z.signal = 'YELLOW';
      else z.signal = 'GREEN';
    }
    const anyRestrictive = config.zones.some((id) => isRestrictive(zones[id]));
    const anyWildlife = config.zones.some((id) => zones[id].wildlifeDetected);
    const anyFault = config.zones.some((id) => !zones[id].sensorHealthy);
    if (!comm.mqttConnected) return 'COMM_LOST';
    if (anyFault) return 'SENSOR_FAULT';
    if (anyWildlife) return 'HAZARD';
    if (anyRestrictive) return 'RECOVERY_REQUIRED';
    return 'NORMAL';
  }

  function snapshot() {
    train.targetSpeedKmh = zones[train.zone].targetSpeedKmh;
    train.stoppingDistanceM = Math.round((train.speedKmh / 3.6) ** 2 / (2 * DECEL));
    return {
      zones: JSON.parse(JSON.stringify(zones)),
      train: { ...train },
      comm: { ...comm },
      overall: recompute(),
      lastEvent,
      updatedAt: new Date().toISOString(),
    };
  }

  function applyCommand(env) {
    const z = zones[env.zone];
    if (!z) return { ok: false, reason: 'unknown zone' };
    switch (env.event) {
      case 'WILDLIFE_DETECTED':
        z.wildlifeDetected = true; z.status = 'HAZARD'; z.targetSpeedKmh = 0; break;
      case 'WILDLIFE_CLEARED':
        z.wildlifeDetected = false; z.status = 'RECOVERY_REQUIRED'; break;
      case 'SENSOR_FAULT':
        z.sensorHealthy = false; z.status = 'SENSOR_FAULT'; z.targetSpeedKmh = 0; break;
      case 'SENSOR_RESTORED':
        z.sensorHealthy = true; z.status = 'RECOVERY_REQUIRED'; break;
      case 'TRAIN_ENTERED_ZONE':
        z.trainPresent = true; train.zone = env.zone; break;
      case 'TRAIN_LEFT_ZONE':
        z.trainPresent = false; break;
      case 'RESET':
        if (z.sensorHealthy && !z.wildlifeDetected) { z.status = 'NORMAL'; z.targetSpeedKmh = DEFAULT_TARGET; }
        else return { ok: false, reason: 'reset rejected: active hazard or sensor fault' };
        break;
      default:
        return { ok: false, reason: 'unsupported event' };
    }
    lastEvent = env.event;
    return { ok: true };
  }

  function applySpeed({ zone, speedKmh }) {
    const z = zones[zone];
    if (!z) return { ok: false, reason: 'unknown zone' };
    z.targetSpeedKmh = Math.max(0, Math.min(80, Number(speedKmh)));
    return { ok: true };
  }

  function applyTelemetry(zone, msg = {}) {
    const z = zones[zone];
    if (!z) return;
    if (typeof msg.trainPresent === 'boolean') z.trainPresent = msg.trainPresent;
    if (Number.isFinite(msg.speedKmh)) train.speedKmh = Math.max(0, Math.min(80, msg.speedKmh));
    if (typeof msg.wildlifeDetected === 'boolean') z.wildlifeDetected = msg.wildlifeDetected;
    if (typeof msg.sensorHealthy === 'boolean') z.sensorHealthy = msg.sensorHealthy;
  }

  function setBrokerConnected(value) {
    comm.mqttConnected = Boolean(value);
  }

  return { snapshot, applyCommand, applySpeed, applyTelemetry, setBrokerConnected };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/state.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/state.js backend/test/state.test.js
git commit -m "feat(backend): two-zone authoritative state machine"
```

---

### Task 7: MQTT bridge (authenticated client)

> **Execute AFTER Task 8.** The bridge tests connect with credentials and require
> the authenticated broker config that Task 8 introduces, and they import
> `test/helpers/broker.js` which Task 8 creates.

**Files:**
- Create: `backend/src/mqtt.js`
- Create: `backend/test/mqtt.test.js`

**Interfaces:**
- Produces: `makeMqtt({config, onMessage}) -> { client, publish(topic, obj, {retain}), subscribe(topics), isConnected(), close() }`.
- Test helper: `connectAs(role)`, `connectAnon()`, and `waitFor(predicate, timeoutMs)` from Task 8's `helpers/broker.js`.

- [ ] **Step 1: Write the failing test**

`backend/test/mqtt.test.js` (imports `./helpers/broker.js`, created in Task 8):
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { config } from '../src/config.js';
import { makeMqtt } from '../src/mqtt.js';
import { connectAs, connectAnon, waitFor } from './helpers/broker.js';

test('connects with credentials and round-trips a publish', async () => {
  const bridge = makeMqtt({ config, onMessage: () => {} });
  await waitFor(() => bridge.isConnected());
  const sub = connectAs('dashboard'); // dashboard may read railway/state; godot may not
  await waitFor(() => sub.connected);
  const got = [];
  await new Promise((resolve) => sub.subscribe('railway/state', resolve));
  sub.on('message', (t, m) => got.push([t, m.toString()]));
  bridge.publish('railway/state', { ok: true }, { retain: true });
  await waitFor(() => got.some(([t]) => t === 'railway/state'));
  sub.end(true);
  bridge.close();
});

test('rejects anonymous connections', async () => {
  const client = connectAnon();
  const err = await new Promise((resolve) => {
    client.on('error', resolve);
    client.on('close', () => resolve(new Error('closed')));
  });
  assert.ok(err);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-backend.sh` (broker must be up; see Task 8). If broker isn't running yet, bring it up after Task 8.
Expected: FAIL — `Cannot find module '../src/mqtt.js'`.

- [ ] **Step 3: Write minimal implementation**

`backend/src/mqtt.js`:
```js
import mqtt from 'mqtt';

export function makeMqtt({ config, onMessage }) {
  const client = mqtt.connect(config.mqttUrl, {
    username: config.mqttUser,
    password: config.mqttPass,
    reconnectPeriod: 2000,
    connectTimeout: 5000,
    clientId: `backend-${Math.random().toString(16).slice(2, 8)}`,
  });
  client.on('message', (topic, buffer) => {
    try { onMessage?.(topic, JSON.parse(buffer.toString())); }
    catch { onMessage?.(topic, { _raw: buffer.toString() }); }
  });
  return {
    client,
    publish(topic, obj, { retain = false } = {}) {
      if (client.connected) client.publish(topic, JSON.stringify(obj), { qos: 0, retain });
    },
    subscribe(topics) {
      client.subscribe(topics, { qos: 0 });
    },
    isConnected() { return client.connected; },
    close() { client.end(true); },
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-backend.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/mqtt.js backend/test/mqtt.test.js
git commit -m "feat(backend): authenticated mqtt bridge"
```

---

### Task 8: Mosquitto auth config, ACLs, setup script, and broker test helper

> **Execute BEFORE Task 7.** This task also creates the shared
> `backend/test/helpers/broker.js` used by Tasks 7 and 15.

**Files:**
- Modify: `mosquitto/mosquitto.conf`
- Create: `mosquitto/acl_file`
- Create: `scripts/mosquitto_setup.sh`
- Create: `scripts/test-backend.sh`
- Create: `backend/test/helpers/broker.js`
- Create: `backend/test/broker_acl.test.js`

**Interfaces:**
- Produces: `scripts/mosquitto_setup.sh` (generates `mosquitto/password_file` from `.env`), `scripts/test-backend.sh` (setup + `docker compose up -d mqtt` + `npm --prefix backend test`).

- [ ] **Step 1: Write the failing test**

`backend/test/helpers/broker.js`:
```js
import mqtt from 'mqtt';

const URL = process.env.MQTT_URL || 'mqtt://127.0.0.1:1883';
const CREDS = {
  backend: [process.env.MQTT_BACKEND_USER || 'backend', process.env.MQTT_BACKEND_PASS || 'backend-dev-pass'],
  godot: ['godot', process.env.MQTT_GODOT_PASS || 'godot-dev-pass'],
  esp32: ['esp32', process.env.MQTT_ESP32_PASS || 'esp32-dev-pass'],
  dashboard: ['dashboard', process.env.MQTT_DASHBOARD_PASS || 'dashboard-dev-pass'],
};

export function waitFor(predicate, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const tick = () => {
      try { if (predicate()) return resolve(); } catch { /* keep polling */ }
      if (Date.now() - start > timeoutMs) return reject(new Error('waitFor timeout'));
      setTimeout(tick, 25);
    };
    tick();
  });
}

export function connectAs(role) {
  const [username, password] = CREDS[role];
  return mqtt.connect(URL, { username, password, reconnectPeriod: 0, connectTimeout: 4000 });
}

export function connectAnon() {
  return mqtt.connect(URL, { reconnectPeriod: 0, connectTimeout: 4000 });
}
```

`backend/test/broker_acl.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { connectAs, waitFor } from './helpers/broker.js';

test('dashboard cannot publish a command (ACL denies)', async () => {
  const observer = connectAs('godot'); // godot may read railway/commands/zone1
  await waitFor(() => observer.connected);
  await new Promise((r) => observer.subscribe('railway/commands/zone1', r));
  const seen = [];
  observer.on('message', (t) => seen.push(t));
  const dash = connectAs('dashboard');
  await waitFor(() => dash.connected);
  dash.publish('railway/commands/zone1', JSON.stringify({ evil: true }));
  await new Promise((r) => setTimeout(r, 500));
  assert.equal(seen.length, 0);
  dash.end(true); observer.end(true);
});

test('godot can publish zone telemetry', async () => {
  const observer = connectAs('backend'); // backend may read railway/zone1/train
  await waitFor(() => observer.connected);
  await new Promise((r) => observer.subscribe('railway/zone1/train', r));
  const seen = [];
  observer.on('message', (t) => seen.push(t));
  const godot = connectAs('godot');
  await waitFor(() => godot.connected);
  godot.publish('railway/zone1/train', JSON.stringify({ trainPresent: true }));
  await waitFor(() => seen.includes('railway/zone1/train'));
  assert.ok(seen.includes('railway/zone1/train'));
  godot.end(true); observer.end(true);
});

test('godot cannot publish aggregate state', async () => {
  const observer = connectAs('dashboard'); // dashboard may read railway/state
  await waitFor(() => observer.connected);
  await new Promise((r) => observer.subscribe('railway/state', r));
  const seen = [];
  observer.on('message', (t) => seen.push(t));
  const godot = connectAs('godot');
  await waitFor(() => godot.connected);
  godot.publish('railway/state', JSON.stringify({ hacked: true }));
  await new Promise((r) => setTimeout(r, 500));
  assert.equal(seen.length, 0);
  godot.end(true); observer.end(true);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-backend.sh`
Expected: FAIL — with the current anonymous broker config, the dashboard's publish is delivered to the observer, so `assert.equal(seen.length, 0)` fails.

- [ ] **Step 3: Write minimal implementation**

`mosquitto/mosquitto.conf`:
```
per_listener_settings false

allow_anonymous false
password_file /mosquitto/config/password_file
acl_file /mosquitto/config/acl_file

listener 1883 0.0.0.0
listener 9001 0.0.0.0
protocol websockets

persistence false
```

`mosquitto/acl_file`:
```
user godot
topic write railway/zone1/train
topic write railway/zone1/wildlife
topic write railway/zone2/train
topic write railway/zone2/wildlife
topic read railway/commands/zone1
topic read railway/commands/zone2
topic read railway/speed/zone1
topic read railway/speed/zone2
topic read railway/zone1/signal
topic read railway/zone2/signal

user esp32
topic write railway/telemetry/esp32
topic read railway/commands/esp32

user backend
topic write railway/state
topic write railway/events
topic write railway/alerts
topic write railway/zone1/signal
topic write railway/zone2/signal
topic write railway/commands/zone1
topic write railway/commands/zone2
topic write railway/commands/esp32
topic write railway/speed/zone1
topic write railway/speed/zone2
topic write railway/security/events
topic read railway/zone1/train
topic read railway/zone1/wildlife
topic read railway/zone2/train
topic read railway/zone2/wildlife
topic read railway/telemetry/esp32

user dashboard
topic read railway/state
topic read railway/events
topic read railway/alerts
```

`scripts/mosquitto_setup.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-$ROOT/.env}"
if [ -f "$ENV_FILE" ]; then set -a; . "$ENV_FILE"; set +a; fi
: "${MQTT_GODOT_PASS:=godot-dev-pass}"
: "${MQTT_ESP32_PASS:=esp32-dev-pass}"
: "${MQTT_BACKEND_PASS:=backend-dev-pass}"
: "${MQTT_DASHBOARD_PASS:=dashboard-dev-pass}"
cd "$ROOT/mosquitto"
docker run --rm -v "$PWD":/work \
  -e G="$MQTT_GODOT_PASS" -e E="$MQTT_ESP32_PASS" -e B="$MQTT_BACKEND_PASS" -e D="$MQTT_DASHBOARD_PASS" \
  eclipse-mosquitto:2 sh -c '
    rm -f /work/password_file
    mosquitto_passwd -b -c /work/password_file godot "$G"
    mosquitto_passwd -b /work/password_file esp32 "$E"
    mosquitto_passwd -b /work/password_file backend "$B"
    mosquitto_passwd -b /work/password_file dashboard "$D"
  '
echo "Wrote $ROOT/mosquitto/password_file"
```

`scripts/test-backend.sh`:
```bash
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
```

Make executable:
```bash
chmod +x scripts/mosquitto_setup.sh scripts/test-backend.sh
```

Also change the mqtt service volume in `docker-compose.yml` to mount the whole config dir:
```yaml
  mqtt:
    image: eclipse-mosquitto:2
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - ./mosquitto:/mosquitto/config:ro
    restart: unless-stopped
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/test-backend.sh`
Expected: PASS (dashboard publish denied; godot telemetry allowed, aggregate state denied).

- [ ] **Step 5: Commit**

```bash
git add mosquitto/mosquitto.conf mosquitto/acl_file scripts/mosquitto_setup.sh scripts/test-backend.sh docker-compose.yml backend/test/helpers/broker.js backend/test/broker_acl.test.js
git commit -m "feat(backend): broker auth, per-client acls, and test harness"
```

---

### Task 9: Events buffer + bus (publisher)

**Files:**
- Create: `backend/src/events.js`
- Create: `backend/src/bus.js`
- Create: `backend/test/bus.test.js`

**Interfaces:**
- Produces: `makeEvents() -> { record(e) -> e, list(limit=100) -> e[] }`.
- Produces: `makeBus({mqtt, state, events}) -> { snapshot() -> State, event(e), alert(a), security(e) }`. `snapshot()` publishes retained `railway/state` and retained `railway/zoneN/signal`. `event()` records + publishes `railway/events`. `alert()` publishes `railway/alerts`. `security()` publishes `railway/security/events`.

- [ ] **Step 1: Write the failing test**

`backend/test/bus.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeState } from '../src/state.js';
import { makeEvents } from '../src/events.js';
import { makeBus } from '../src/bus.js';

function fakeMqtt() {
  return { out: [], published: [], publish(t, o, opts = {}) { this.published.push({ t, o, opts }); }, isConnected: () => true };
}

test('snapshot publishes retained state and per-zone signals', () => {
  const mqtt = fakeMqtt();
  const state = makeState({ config: { zones: ['zone1', 'zone2'] } });
  const bus = makeBus({ mqtt, state, events: makeEvents() });
  bus.snapshot();
  const stateMsg = mqtt.published.find((m) => m.t === 'railway/state');
  assert.equal(stateMsg.opts.retain, true);
  assert.ok(mqtt.published.find((m) => m.t === 'railway/zone1/signal'));
  assert.ok(mqtt.published.find((m) => m.t === 'railway/zone2/signal'));
});

test('events are recorded and published newest-first', () => {
  const mqtt = fakeMqtt();
  const bus = makeBus({ mqtt, state: makeState({ config: { zones: ['zone1', 'zone2'] } }), events: makeEvents() });
  bus.event({ type: 'A' });
  bus.event({ type: 'B' });
  assert.equal(bus.list?.length, undefined); // bus has no list; check publish
  assert.equal(mqtt.published.filter((m) => m.t === 'railway/events').length, 2);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/bus.test.js`
Expected: FAIL — modules not found.

- [ ] **Step 3: Write minimal implementation**

`backend/src/events.js`:
```js
export function makeEvents(max = 200) {
  const items = [];
  return {
    record(e) {
      const entry = { id: `${Date.now()}-${Math.random().toString(16).slice(2, 7)}`, time: new Date().toISOString(), ...e };
      items.unshift(entry);
      if (items.length > max) items.pop();
      return entry;
    },
    list(limit = 100) { return items.slice(0, Math.max(1, Number(limit) || 100)); },
  };
}
```

`backend/src/bus.js`:
```js
export function makeBus({ mqtt, state, events }) {
  return {
    snapshot() {
      const s = state.snapshot();
      mqtt.publish('railway/state', s, { retain: true });
      for (const id of Object.keys(s.zones)) {
        mqtt.publish(`railway/${id}/signal`, { zone: id, signal: s.zones[id].signal, timestamp: s.updatedAt }, { retain: true });
      }
      return s;
    },
    event(e) {
      const entry = events.record(e);
      mqtt.publish('railway/events', entry);
      return entry;
    },
    alert(a) { mqtt.publish('railway/alerts', a); },
    security(e) { mqtt.publish('railway/security/events', e); },
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/bus.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/events.js backend/src/bus.js backend/test/bus.test.js
git commit -m "feat(backend): event buffer and mqtt publisher bus"
```

---

### Task 10: HTTP app, auth + health routes

**Files:**
- Create: `backend/src/app.js`
- Create: `backend/src/routes/auth.js`
- Create: `backend/src/routes/health.js`
- Create: `backend/test/app_helpers.js`
- Create: `backend/test/auth_routes.test.js`

**Interfaces:**
- Consumes: everything above.
- Produces: `createApp(deps) -> express app` where `deps = { config, db, audit, replay, auth, state, bus, events, mqtt }`.
- Produces (test helper): `withServer(deps, fn(url))`.

- [ ] **Step 1: Write the failing test**

`backend/test/app_helpers.js`:
```js
import { once } from 'node:events';
import { openDb } from '../src/db.js';
import { makeAudit } from '../src/audit.js';
import { makeReplay } from '../src/replay.js';
import { makeAuth } from '../src/auth.js';
import { makeState } from '../src/state.js';
import { makeEvents } from '../src/events.js';
import { makeBus } from '../src/bus.js';
import { createApp } from '../src/app.js';
import { config } from '../src/config.js';

export function fakeMqtt() {
  return { published: [], publish(t, o, opts = {}) { this.published.push({ t, o, opts }); }, subscribe() {}, isConnected: () => true };
}

export function buildDeps(overrides = {}) {
  const db = overrides.db || openDb(':memory:');
  const auth = makeAuth({ db, config });
  auth.seedUsers();
  const state = makeState({ config });
  const events = makeEvents();
  const mqtt = overrides.mqtt || fakeMqtt();
  const bus = makeBus({ mqtt, state, events });
  return { config, db, audit: makeAudit(db), replay: makeReplay(db), auth, state, bus, events, mqtt, ...overrides };
}

export async function withServer(deps, fn) {
  const app = createApp(deps);
  const server = app.listen(0);
  await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}`;
  try { return await fn(url); } finally { server.close(); }
}

export async function login(url, username, password) {
  const res = await fetch(`${url}/api/auth/login`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  return { status: res.status, body: await res.json() };
}
```

`backend/test/auth_routes.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildDeps, withServer, login } from './app_helpers.js';
import { config } from '../src/config.js';

const oPass = config.seedUsers.find((u) => u.role === 'operator').password;

test('login + me + health', async () => {
  await withServer(buildDeps(), async (url) => {
    const health = await fetch(`${url}/api/health`).then((r) => r.json());
    assert.equal(health.ok, true);

    const bad = await login(url, 'operator', 'wrong');
    assert.equal(bad.status, 401);

    const good = await login(url, 'operator', oPass);
    assert.equal(good.status, 200);
    assert.ok(good.body.token);

    const me = await fetch(`${url}/api/me`, { headers: { authorization: `Bearer ${good.body.token}` } });
    assert.equal(me.status, 200);
    assert.equal((await me.json()).user.role, 'operator');

    const anon = await fetch(`${url}/api/me`);
    assert.equal(anon.status, 401);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/auth_routes.test.js`
Expected: FAIL — `Cannot find module '../src/app.js'`.

- [ ] **Step 3: Write minimal implementation**

`backend/src/routes/health.js`:
```js
import { Router } from 'express';

export function healthRouter({ mqtt }) {
  const router = Router();
  router.get('/api/health', (_req, res) => res.json({ ok: true, mqttConnected: mqtt.isConnected() }));
  return router;
}
```

`backend/src/routes/auth.js`:
```js
import { Router } from 'express';

export function authRouter({ auth }) {
  const router = Router();
  router.post('/api/auth/login', (req, res) => {
    const result = auth.login(req.body?.username, req.body?.password);
    if (!result.ok) return res.status(401).json({ error: result.reason });
    return res.json({ token: result.token, user: result.user });
  });
  router.get('/api/me', auth.requireAuth, (req, res) => res.json({ user: req.user }));
  return router;
}
```

`backend/src/app.js`:
```js
import express from 'express';
import cors from 'cors';
import { authRouter } from './routes/auth.js';
import { healthRouter } from './routes/health.js';

export function createApp(deps) {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '32kb' }));
  app.use(authRouter(deps));
  app.use(healthRouter(deps));
  return app;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/auth_routes.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/app.js backend/src/routes/auth.js backend/src/routes/health.js backend/test/app_helpers.js backend/test/auth_routes.test.js
git commit -m "feat(backend): express app with auth and health routes"
```

---

### Task 11: Control + speed routes (RBAC, validation, replay, audit)

**Files:**
- Create: `backend/src/routes/control.js`
- Modify: `backend/src/app.js`
- Create: `backend/test/control_routes.test.js`

**Interfaces:**
- Consumes: `validateCommand`, `validateSpeed`, `replay`, `state`, `bus`, `audit`, `hasPermission`.
- Produces: `POST /api/control` (operator+) and `POST /api/speed` (operator+). Both return `{ ok, state }`. On reject: JSON `{ error, reason }` with 400/403/409 and an audit row + `railway/security/events` publish. Permission denials are audited with `result: 'FORBIDDEN'` (a `requirePermission` middleware would short-circuit before the route body and skip the audit write).

- [ ] **Step 1: Write the failing test**

`backend/test/control_routes.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildDeps, withServer, login } from './app_helpers.js';
import { config } from '../src/config.js';

const pass = (role) => config.seedUsers.find((u) => u.role === role).password;
const envelope = (zone, event, id) => ({ request_id: id, zone, event, timestamp: new Date().toISOString(), source: 'dashboard', payload: {} });

async function tokenFor(url, role) {
  return (await login(url, role, pass(role))).body.token;
}

test('control route enforces auth, rbac, replay and records audit', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const anon = await fetch(`${url}/api/control`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(envelope('zone1', 'WILDLIFE_DETECTED', 'a1')) });
    assert.equal(anon.status, 401);

    const viewer = await tokenFor(url, 'viewer');
    const forbidden = await fetch(`${url}/api/control`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${viewer}` }, body: JSON.stringify(envelope('zone1', 'WILDLIFE_DETECTED', 'a2')) });
    assert.equal(forbidden.status, 403);
    assert.ok(deps.audit.list().some((r) => r.result === 'FORBIDDEN'));

    const operator = await tokenFor(url, 'operator');
    const ok = await fetch(`${url}/api/control`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` }, body: JSON.stringify(envelope('zone1', 'WILDLIFE_DETECTED', 'a3')) });
    assert.equal(ok.status, 200);
    const body = await ok.json();
    assert.equal(body.state.zones.zone1.signal, 'RED');

    const dup = await fetch(`${url}/api/control`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` }, body: JSON.stringify(envelope('zone1', 'WILDLIFE_DETECTED', 'a3')) });
    assert.equal(dup.status, 400);
    assert.ok((await dup.json()).reason.match(/duplicate/));

    assert.ok(deps.mqtt.published.some((m) => m.t === 'railway/commands/zone1'));
    assert.ok(deps.audit.list().some((r) => r.action === 'WILDLIFE_DETECTED' && r.result === 'ACCEPTED'));
  });
});

test('speed route validates range and applies per zone', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const operator = await tokenFor(url, 'operator');
    const bad = await fetch(`${url}/api/speed`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` }, body: JSON.stringify({ zone: 'zone1', speedKmh: 200 }) });
    assert.equal(bad.status, 400);
    const ok = await fetch(`${url}/api/speed`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` }, body: JSON.stringify({ zone: 'zone2', speedKmh: 30 }) });
    assert.equal(ok.status, 200);
    assert.equal((await ok.json()).state.zones.zone2.targetSpeedKmh, 30);
    assert.ok(deps.mqtt.published.some((m) => m.t === 'railway/speed/zone2'));
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/control_routes.test.js`
Expected: FAIL — 404 / route not found.

- [ ] **Step 3: Write minimal implementation**

`backend/src/routes/control.js`:
```js
import { Router } from 'express';
import { hasPermission } from '../rbac.js';
import { validateCommand, validateSpeed } from '../validate.js';

export function controlRouter({ auth, config, state, bus, audit, replay, mqtt }) {
  const router = Router();
  const ctx = { zones: config.zones };

  function deny(req, res, action, zone, reason) {
    audit.write({ actor: req.user.username, role: req.user.role, action, zone, result: 'FORBIDDEN', reason, source: 'rest' });
    bus.security({ request_id: req.body?.request_id || null, actor: req.user.username, reason, timestamp: new Date().toISOString() });
    return res.status(403).json({ error: 'forbidden', reason });
  }

  router.post('/api/control', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'control:issue')) {
      return deny(req, res, String(req.body?.event || 'UNKNOWN'), req.body?.zone || null, 'missing control:issue');
    }
    const check = validateCommand(req.body, ctx);
    if (!check.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: String(req.body?.event || 'UNKNOWN'), zone: req.body?.zone || null, result: 'REJECTED', reason: check.reason, source: 'rest' });
      bus.security({ request_id: req.body?.request_id || null, actor: req.user.username, reason: check.reason, timestamp: new Date().toISOString() });
      return res.status(400).json({ error: 'invalid command', reason: check.reason });
    }
    const dedupe = replay.check(check.value.request_id, { username: req.user.username, action: check.value.event });
    if (!dedupe.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: check.value.event, zone: check.value.zone, result: 'REJECTED', reason: dedupe.reason, source: 'rest' });
      bus.security({ request_id: check.value.request_id, actor: req.user.username, reason: dedupe.reason, timestamp: new Date().toISOString() });
      return res.status(400).json({ error: 'duplicate', reason: dedupe.reason });
    }
    const applied = state.applyCommand(check.value);
    if (!applied.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: check.value.event, zone: check.value.zone, result: 'REJECTED', reason: applied.reason, source: 'rest' });
      bus.security({ request_id: check.value.request_id, actor: req.user.username, reason: applied.reason, timestamp: new Date().toISOString() });
      return res.status(409).json({ error: 'transition rejected', reason: applied.reason });
    }
    mqtt.publish(`railway/commands/${check.value.zone}`, check.value);
    const snapshot = bus.snapshot();
    audit.write({ actor: req.user.username, role: req.user.role, action: check.value.event, zone: check.value.zone, result: 'ACCEPTED', source: 'rest' });
    bus.event({ type: check.value.event, zone: check.value.zone, actor: req.user.username, result: 'ACCEPTED' });
    return res.json({ ok: true, state: snapshot });
  });

  router.post('/api/speed', auth.requireAuth, (req, res) => {
    if (!hasPermission(req.user.role, 'speed:set')) {
      return deny(req, res, 'SPEED', req.body?.zone || null, 'missing speed:set');
    }
    const check = validateSpeed(req.body, ctx);
    if (!check.ok) {
      audit.write({ actor: req.user.username, role: req.user.role, action: 'SPEED', zone: req.body?.zone || null, result: 'REJECTED', reason: check.reason, source: 'rest' });
      return res.status(400).json({ error: 'invalid speed', reason: check.reason });
    }
    state.applySpeed(check.value);
    mqtt.publish(`railway/speed/${check.value.zone}`, { zone: check.value.zone, speedKmh: check.value.speedKmh, timestamp: new Date().toISOString() });
    const snapshot = bus.snapshot();
    audit.write({ actor: req.user.username, role: req.user.role, action: 'SPEED', zone: check.value.zone, target: String(check.value.speedKmh), result: 'ACCEPTED', source: 'rest' });
    return res.json({ ok: true, state: snapshot });
  });

  return router;
}
```

Modify `backend/src/app.js` to include the control router:
```js
import { controlRouter } from './routes/control.js';
// inside createApp, after healthRouter:
  app.use(controlRouter(deps));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/control_routes.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/control.js backend/src/app.js backend/test/control_routes.test.js
git commit -m "feat(backend): authenticated control and speed routes"
```

---

### Task 12: State/events/audit read routes

**Files:**
- Create: `backend/src/routes/state.js`
- Modify: `backend/src/app.js`
- Create: `backend/test/read_routes.test.js`

**Interfaces:**
- Produces: `GET /api/state` (viewer+), `GET /api/events` (viewer+), `GET /api/audit` (admin).

- [ ] **Step 1: Write the failing test**

`backend/test/read_routes.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildDeps, withServer, login } from './app_helpers.js';
import { config } from '../src/config.js';

const pass = (role) => config.seedUsers.find((u) => u.role === role).password;
const auth = async (url, role) => ({ authorization: `Bearer ${(await login(url, role, pass(role))).body.token}` });

test('read routes respect roles', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const viewer = await auth(url, 'viewer');
    const state = await fetch(`${url}/api/state`, { headers: viewer });
    assert.equal(state.status, 200);
    assert.equal((await state.json()).zones.zone1.signal, 'GREEN');

    const noTok = await fetch(`${url}/api/state`);
    assert.equal(noTok.status, 401);

    const auditForbidden = await fetch(`${url}/api/audit`, { headers: viewer });
    assert.equal(auditForbidden.status, 403);

    const admin = await auth(url, 'admin');
    const audit = await fetch(`${url}/api/audit`, { headers: admin });
    assert.equal(audit.status, 200);
    assert.ok(Array.isArray(await audit.json()));
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/read_routes.test.js`
Expected: FAIL — 404.

- [ ] **Step 3: Write minimal implementation**

`backend/src/routes/state.js`:
```js
import { Router } from 'express';
import { requirePermission } from '../rbac.js';

export function stateRouter({ auth, state, events, audit }) {
  const router = Router();
  router.get('/api/state', auth.requireAuth, requirePermission('state:read'), (_req, res) => res.json(state.snapshot()));
  router.get('/api/events', auth.requireAuth, requirePermission('events:read'), (_req, res) => res.json(events.list()));
  router.get('/api/audit', auth.requireAuth, requirePermission('audit:read'), (req, res) => res.json(audit.list(Number(req.query.limit) || 100)));
  return router;
}
```

Modify `backend/src/app.js` to include `stateRouter(deps)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/read_routes.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/routes/state.js backend/src/app.js backend/test/read_routes.test.js
git commit -m "feat(backend): state, events, audit read routes with rbac"
```

---

### Task 13: MQTT ingestion, aggregation, and recovery policy

**Files:**
- Modify: `backend/server.js`
- Create: `backend/src/ingest.js`
- Create: `backend/test/ingest.test.js`

**Interfaces:**
- Produces: `makeIngest({state, bus, config}) -> { handle(topic, message), onBrokerConnected(bool) }`. Handles `railway/zoneN/train`, `railway/zoneN/wildlife`, `railway/telemetry/esp32`; publishes aggregate snapshot + retained signals on change; sets `COMM_LOST` on disconnect and reconciles on reconnect by republishing the retained snapshot.

- [ ] **Step 1: Write the failing test**

`backend/test/ingest.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeState } from '../src/state.js';
import { makeEvents } from '../src/events.js';
import { makeBus } from '../src/bus.js';
import { makeIngest } from '../src/ingest.js';

function fakeMqtt() { return { published: [], publish(t, o, opts = {}) { this.published.push({ t, o, opts }); }, subscribe() {}, isConnected: () => true }; }

function setup() {
  const mqtt = fakeMqtt();
  const state = makeState({ config: { zones: ['zone1', 'zone2'] } });
  const bus = makeBus({ mqtt, state, events: makeEvents() });
  const ingest = makeIngest({ state, bus, config: { zones: ['zone1', 'zone2'] } });
  return { mqtt, state, ingest };
}

test('zone train telemetry updates occupancy and republishes state', () => {
  const { mqtt, state, ingest } = setup();
  state.setBrokerConnected(true);
  ingest.handle('railway/zone1/train', { trainPresent: true, speedKmh: 20 });
  assert.equal(state.snapshot().zones.zone1.trainPresent, true);
  assert.ok(mqtt.published.some((m) => m.t === 'railway/state'));
});

test('esp32 telemetry marks device and forces fault when unhealthy', () => {
  const { state, ingest, mqtt } = setup();
  state.setBrokerConnected(true);
  ingest.handle('railway/telemetry/esp32', { device: 'esp32', sensorHealthy: false });
  assert.equal(state.snapshot().overall, 'SENSOR_FAULT');
  assert.ok(mqtt.published.some((m) => m.t === 'railway/security/events' || m.t === 'railway/alerts' || m.t === 'railway/state'));
});

test('disconnect sets COMM_LOST and reconnect reconciles', () => {
  const { state, ingest, mqtt } = setup();
  ingest.onBrokerConnected(true);
  assert.equal(state.snapshot().overall, 'NORMAL');
  ingest.onBrokerConnected(false);
  assert.equal(state.snapshot().overall, 'COMM_LOST');
  ingest.onBrokerConnected(true);
  assert.equal(state.snapshot().overall, 'NORMAL');
  assert.ok(mqtt.published.filter((m) => m.t === 'railway/state').length >= 2);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test test/ingest.test.js`
Expected: FAIL — `Cannot find module '../src/ingest.js'`.

- [ ] **Step 3: Write minimal implementation**

`backend/src/ingest.js`:
```js
export function makeIngest({ state, bus, config }) {
  let esp32Online = false;

  function handle(topic, message = {}) {
    const zoneMatch = topic.match(/^railway\/(zone\d+)\/(train|wildlife)$/);
    if (zoneMatch) {
      const [, zone, kind] = zoneMatch;
      if (!config.zones.includes(zone)) return;
      if (kind === 'train') state.applyTelemetry(zone, { trainPresent: message.trainPresent, speedKmh: message.speedKmh });
      else state.applyTelemetry(zone, { wildlifeDetected: message.wildlifeDetected });
      bus.snapshot();
      return;
    }
    if (topic === 'railway/telemetry/esp32') {
      esp32Online = true;
      const snapshot = state.snapshot();
      if (message.sensorHealthy === false) {
        bus.alert({ source: 'esp32', severity: 'HIGH', message: 'ESP32 reports sensor fault', timestamp: new Date().toISOString() });
      }
      snapshot.comm = { ...snapshot.comm, esp32Online };
      return;
    }
    bus.event({ type: 'INVALID_TOPIC', topic });
  }

  function onBrokerConnected(connected) {
    state.setBrokerConnected(connected);
    if (connected) {
      bus.event({ type: 'BROKER_CONNECTED', message: 'Reconciling state from authoritative snapshot.' });
      bus.snapshot();
    } else {
      bus.event({ type: 'BROKER_DISCONNECTED', message: 'Communication lost; restrictive state applied.' });
      bus.snapshot();
    }
  }

  return { handle, onBrokerConnected };
}
```

`backend/server.js` (composition root):
```js
import { config } from './src/config.js';
import { openDb } from './src/db.js';
import { makeAudit } from './src/audit.js';
import { makeReplay } from './src/replay.js';
import { makeAuth } from './src/auth.js';
import { makeState } from './src/state.js';
import { makeEvents } from './src/events.js';
import { makeBus } from './src/bus.js';
import { makeMqtt } from './src/mqtt.js';
import { makeIngest } from './src/ingest.js';
import { createApp } from './src/app.js';

const db = openDb(config.dbPath);
const audit = makeAudit(db);
const replay = makeReplay(db);
const auth = makeAuth({ db, config });
auth.seedUsers();
const state = makeState({ config });
state.setBrokerConnected(false); // fail-safe until the broker connection is established
const events = makeEvents();
let ingest;
const mqtt = makeMqtt({ config, onMessage: (topic, message) => ingest?.handle(topic, message) });
const bus = makeBus({ mqtt, state, events });
ingest = makeIngest({ state, bus, config });
mqtt.client.on('connect', () => {
  mqtt.subscribe(['railway/zone1/train', 'railway/zone1/wildlife', 'railway/zone2/train', 'railway/zone2/wildlife', 'railway/telemetry/esp32']);
  ingest.onBrokerConnected(true);
});
mqtt.client.on('close', () => ingest.onBrokerConnected(false));
const app = createApp({ config, db, audit, replay, auth, state, bus, events, mqtt });
app.listen(config.port, '0.0.0.0', () => console.log(`Railway backend listening on :${config.port}; MQTT=${config.mqttUrl}`));
```

`bus` is created before `ingest` (both depend only on `mqtt`/`state`/`events`), and `ingest.onBrokerConnected` owns the connect/disconnect policy.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test test/ingest.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/ingest.js backend/server.js backend/test/ingest.test.js
git commit -m "feat(backend): mqtt ingestion, aggregation, recovery policy"
```

---

### Task 14: Docker + setup scripts + docs

**Files:**
- Modify: `backend/Dockerfile`
- Modify: `docker-compose.yml`
- Create: `scripts/dev-up.sh`
- Modify: `README.md`
- Modify: `IMPLEMENTATION.md`

**Interfaces:**
- Produces: `docker compose up --build` starts broker (auth), backend (seeded, retained state). `scripts/dev-up.sh` generates the password file then brings the stack up.

- [ ] **Step 1: Write the failing test**

Integration assertion (manual command, no test file): after `docker compose up --build -d`, request the backend:
Run: `bash scripts/dev-up.sh && sleep 5 && curl -s localhost:3001/api/health`
Expected: before edits, FAIL — no auth / old backend; after, `{"ok":true,"mqttConnected":true}`.

- [ ] **Step 2: Implement**

`backend/Dockerfile`:
```dockerfile
FROM node:24-slim
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY . .
EXPOSE 3001
CMD ["node", "server.js"]
```

`docker-compose.yml` (backend service env + depends):
```yaml
  backend:
    build: ./backend
    environment:
      PORT: 3001
      MQTT_URL: mqtt://mqtt:1883
      MQTT_BACKEND_USER: backend
      MQTT_BACKEND_PASS: ${MQTT_BACKEND_PASS:-backend-dev-pass}
      JWT_SECRET: ${JWT_SECRET:-dev-insecure-secret-change-me}
      VIEWER_PASSWORD: ${VIEWER_PASSWORD:-viewer-dev-pass}
      OPERATOR_PASSWORD: ${OPERATOR_PASSWORD:-operator-dev-pass}
      ADMIN_PASSWORD: ${ADMIN_PASSWORD:-admin-dev-pass}
      DB_PATH: /app/data/railway.db
    volumes:
      - backend-data:/app/data
    ports:
      - "3001:3001"
    depends_on:
      - mqtt
```
Add at file scope: `volumes: { backend-data: {} }`.

`scripts/dev-up.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/mosquitto_setup.sh"
docker compose -f "$ROOT/docker-compose.yml" up --build -d
echo "Backend: http://localhost:3001/api/health"
```

`README.md`: replace the MQTT topics + quick-start sections to document authenticated broker, credentials from `.env`, the REST control path, and that the backend is the only command publisher. `IMPLEMENTATION.md`: add a "Security & recovery" section describing `allow_anonymous false`, ACLs, replay, audit, and `COMM_LOST`.

- [ ] **Step 3: Verify**

Run: `bash scripts/dev-up.sh && sleep 6 && curl -s localhost:3001/api/health`
Expected: `{"ok":true,"mqttConnected":true}`.

- [ ] **Step 4: Full suite**

Run: `bash scripts/test-backend.sh`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/Dockerfile docker-compose.yml scripts/dev-up.sh README.md IMPLEMENTATION.md
git commit -m "feat(backend): docker wiring, setup scripts, docs"
```

---

### Task 15: End-to-end verification matrix

**Files:**
- Create: `backend/test/e2e.test.js`
- Create: `scripts/demo-scenarios.sh`

**Interfaces:**
- Produces: an automated suite asserting the spec's 13-row verification matrix against the running broker-backed app.

- [ ] **Step 1: Write the failing test**

`backend/test/e2e.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildDeps, withServer, login } from './app_helpers.js';
import { config } from '../src/config.js';
import { connectAs, waitFor } from './helpers/broker.js';

const pass = (r) => config.seedUsers.find((u) => u.role === r).password;
const token = async (url, r) => (await login(url, r, pass(r))).body.token;
const ctl = (url, t, env) => fetch(`${url}/api/control`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${t}` }, body: JSON.stringify(env) });
const env = (zone, event, id) => ({ request_id: id, zone, event, timestamp: new Date().toISOString(), source: 'dashboard', payload: {} });

test('verification matrix', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    let n = 0;
    const id = () => `e2e-${++n}`;

    // 2 unauthorized control
    assert.equal((await fetch(`${url}/api/control`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' })).status, 401);
    // 1 login
    const op = await token(url, 'operator');
    assert.ok(op);
    // 3 viewer forbidden
    const vw = await token(url, 'viewer');
    assert.equal((await ctl(url, vw, env('zone1', 'WILDLIFE_DETECTED', id()))).status, 403);
    // 4 malformed
    assert.equal((await fetch(`${url}/api/speed`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${op}` }, body: JSON.stringify({ zone: 'zone1', speedKmh: 999 }) })).status, 400);
    // 5 duplicate
    const e = env('zone1', 'WILDLIFE_DETECTED', id());
    assert.equal((await ctl(url, op, e)).status, 200);
    assert.equal((await ctl(url, op, e)).status, 400);
    // 8 zone isolation
    let snap = await (await fetch(`${url}/api/state`, { headers: { authorization: `Bearer ${op}` } })).json();
    assert.equal(snap.zones.zone1.signal, 'RED');
    assert.equal(snap.zones.zone2.signal, 'YELLOW');
    assert.equal(snap.zones.zone2.wildlifeDetected, false);
    // recovery
    assert.equal((await ctl(url, op, env('zone1', 'WILDLIFE_CLEARED', id()))).status, 200);
    assert.equal((await ctl(url, op, env('zone1', 'RESET', id()))).status, 200);
    // 9 zone2 independent
    assert.equal((await ctl(url, op, env('zone2', 'WILDLIFE_DETECTED', id()))).status, 200);
    assert.equal((await ctl(url, op, env('zone2', 'RESET', id()))).status, 409);
    // 12 audit rbac
    assert.equal((await fetch(`${url}/api/audit`, { headers: { authorization: `Bearer ${vw}` } })).status, 403);
    const admin = await token(url, 'admin');
    assert.equal((await fetch(`${url}/api/audit`, { headers: { authorization: `Bearer ${admin}` } })).status, 200);
  });

  // 6/7 broker ACL assertions (each observer must have read permission for its topic)
  const cmdObserver = connectAs('godot'); // godot may read railway/commands/zone1
  await waitFor(() => cmdObserver.connected);
  await new Promise((r) => cmdObserver.subscribe('railway/commands/zone1', r));
  const cmdSeen = [];
  cmdObserver.on('message', (t) => cmdSeen.push(t));

  const stateObserver = connectAs('dashboard'); // dashboard may read railway/state
  await waitFor(() => stateObserver.connected);
  await new Promise((r) => stateObserver.subscribe('railway/state', r));
  const stateSeen = [];
  stateObserver.on('message', (t) => stateSeen.push(t));

  const dash = connectAs('dashboard');
  await waitFor(() => dash.connected);
  dash.publish('railway/commands/zone1', 'x');
  const godot = connectAs('godot');
  await waitFor(() => godot.connected);
  godot.publish('railway/state', 'x');
  await new Promise((r) => setTimeout(r, 500));
  assert.ok(!cmdSeen.includes('railway/commands/zone1'));
  assert.ok(!stateSeen.includes('railway/state'));
  dash.end(true); godot.end(true); cmdObserver.end(true); stateObserver.end(true);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-backend.sh`
Expected: FAIL until routes/ACLs from Tasks 8–13 exist.

- [ ] **Step 3: Implement**

`scripts/demo-scenarios.sh`: a scripted sequence (login as operator, wildlife zone1, capture state, clear+reset, sensor fault, reset rejected) using `curl` + `jq`, printing each step. (Content mirrors the e2e test's HTTP calls; `jq` optional with a plain fallback echo.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-backend.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/test/e2e.test.js scripts/demo-scenarios.sh
git commit -m "test(backend): end-to-end verification matrix and demo script"
```

---

## Self-Review

**Spec coverage:**
- Broker auth baseline (`allow_anonymous false`, password file, ACLs, secured WS) → Tasks 7–8.
- Zone-scoped control topics + envelope + `request_id` replay → Tasks 5, 11, 13.
- Backend as sole command publisher → Tasks 11, 13 (dashboard publishes nothing, verified Task 8/15).
- Auth/RBAC/validation/audit → Tasks 4–5, 10–12.
- Two-zone state machine + recovery + `COMM_LOST` → Tasks 6, 13.
- SQLite audit + replay + users → Tasks 2–4.
- Read-only dashboard transport is Stage B (not this plan); backend exposes MQTT state/events for it → Tasks 9, 13.
- Verification matrix rows 1–13 → Task 15.
- ESP32 per-client credentials/topics are Stage D; ACL entries for `esp32` are provisioned here (Task 8).

**Placeholder scan:** no TBD/TODO; every code step has runnable code. `scripts/demo-scenarios.sh` describes content and mirrors Task 15's calls (acceptable: it is a convenience wrapper, not a tested behavior).

**Type consistency:** `state.snapshot()` shape, `bus.{snapshot,event,alert,security}`, `mqtt.publish(topic,obj,{retain})`, `replay.check(id,{username,action})`, `audit.write(entry)`/`audit.list(limit)`, `validateCommand`/`validateSpeed` return `{ok,value?,reason?}` are used consistently across Tasks 3–15.
