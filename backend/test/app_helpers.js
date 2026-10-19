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
  const resolvedConfig = overrides.config || config;
  const db = overrides.db || openDb(':memory:');
  const auth = makeAuth({ db, config: resolvedConfig });
  auth.seedUsers();
  const state = makeState({ config: resolvedConfig });
  const events = makeEvents();
  const mqtt = overrides.mqtt || fakeMqtt();
  const bus = makeBus({ mqtt, state, events });
  return { config: resolvedConfig, db, audit: makeAudit(db), replay: makeReplay(db), auth, state, bus, events, mqtt, ...overrides };
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
