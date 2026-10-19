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
  stateObserver.on('message', (t, m) => {
    try {
      if (JSON.parse(m.toString()).x) stateSeen.push(t);
    } catch {
      stateSeen.push(t);
    }
  });

  const dash = connectAs('dashboard');
  await waitFor(() => dash.connected);
  dash.publish('railway/commands/zone1', JSON.stringify({ x: true }));
  const godot = connectAs('godot');
  await waitFor(() => godot.connected);
  godot.publish('railway/state', JSON.stringify({ x: true }));
  await new Promise((r) => setTimeout(r, 500));
  assert.ok(!cmdSeen.includes('railway/commands/zone1'));
  assert.ok(!stateSeen.includes('railway/state'));
  dash.end(true); godot.end(true); cmdObserver.end(true); stateObserver.end(true);
});
