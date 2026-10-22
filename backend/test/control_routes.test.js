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
    assert.ok(deps.mqtt.published.some((m) => m.t === 'railway/security/events'));
    const ok = await fetch(`${url}/api/speed`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` }, body: JSON.stringify({ zone: 'zone2', speedKmh: 30 }) });
    assert.equal(ok.status, 200);
    assert.equal((await ok.json()).state.zones.zone2.targetSpeedKmh, 30);
    assert.ok(deps.mqtt.published.some((m) => m.t === 'railway/speed/zone2'));
  });
});

test('only accepted commands for the configured ESP32 zone are forwarded', async () => {
  const deps = buildDeps({ config: { ...config, esp32Zone: 'zone1' } });
  await withServer(deps, async (url) => {
    const operator = await tokenFor(url, 'operator');
    const post = (body) => fetch(`${url}/api/control`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` },
      body: JSON.stringify(body),
    });

    const accepted = await post(envelope('zone1', 'WILDLIFE_DETECTED', 'esp-forward-1'));
    assert.equal(accepted.status, 200);
    const forwards = () => deps.mqtt.published.filter((m) => m.t === 'railway/commands/esp32');
    assert.equal(forwards().length, 1);
    assert.equal(forwards()[0].o.zone, 'zone1');

    const otherZone = await post(envelope('zone2', 'WILDLIFE_DETECTED', 'esp-forward-2'));
    assert.equal(otherZone.status, 200);
    assert.equal(forwards().length, 1);

    const duplicate = await post(envelope('zone1', 'WILDLIFE_DETECTED', 'esp-forward-1'));
    assert.equal(duplicate.status, 400);
    assert.equal(forwards().length, 1);

    const invalid = await post({ request_id: 'esp-forward-invalid', zone: 'zone1', event: 'NOT_A_COMMAND' });
    assert.equal(invalid.status, 400);
    assert.equal(forwards().length, 1);
  });
});

test('speed route accepts per-train control and rejects unknown trains', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const operator = await tokenFor(url, 'operator');
    const post = (body) => fetch(`${url}/api/speed`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` },
      body: JSON.stringify(body),
    });
    const bad = await post({ trainId: 'NOPE', speedKmh: 30 });
    assert.equal(bad.status, 400);
    const ok = await post({ trainId: 'T1', speedKmh: 30 });
    assert.equal(ok.status, 200);
    assert.equal((await ok.json()).state.trains[0].targetSpeedKmh, 30);
    assert.ok(deps.mqtt.published.some((m) => m.t === 'railway/speed/zone1'));
  });
});

test('route endpoint requires auth, role and a valid crossover', async () => {
  const fleet = { ...config, trains: [{ ...config.trains[0], startBlock: 2 }, config.trains[1]] };
  const deps = buildDeps({ config: fleet });
  await withServer(deps, async (url) => {
    const body = (id, trainId, routeId) => ({ request_id: id, trainId, routeId });
    const anon = await fetch(`${url}/api/route`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body('r0', 'T1', 'X-UP-DOWN')) });
    assert.equal(anon.status, 401);

    const viewer = await tokenFor(url, 'viewer');
    const denied = await fetch(`${url}/api/route`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${viewer}` }, body: JSON.stringify(body('r1', 'T1', 'X-UP-DOWN')) });
    assert.equal(denied.status, 403);

    const operator = await tokenFor(url, 'operator');
    const post = (b) => fetch(`${url}/api/route`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` },
      body: JSON.stringify(b),
    });
    const unknown = await post(body('r2', 'T1', 'NOPE'));
    assert.equal(unknown.status, 400);

    const ok = await post(body('r3', 'T1', 'X-UP-DOWN'));
    assert.equal(ok.status, 200);
    const state = (await ok.json()).state;
    assert.equal(state.trains[0].line, 'DOWN');
    assert.equal(state.routes.active.routeId, 'X-UP-DOWN');

    const duplicate = await post(body('r3', 'T1', 'X-UP-DOWN'));
    assert.equal(duplicate.status, 400);

    const conflict = await post(body('r4', 'T1', 'X-DOWN-UP'));
    assert.equal(conflict.status, 409);
    assert.ok(deps.audit.list().some((r) => r.action === 'ROUTE' && r.result === 'ACCEPTED'));
  });
});

test('legacy POST /api/event is gone', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const res = await fetch(`${url}/api/event`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ type: 'RESET', zone: 'zone1' }) });
    assert.equal(res.status, 404);
  });
});

test('meet control enforces auth, rbac, validation, replay and audit', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const body = { request_id: 'meet-1', enabled: true, seed: 99 };
    const anon = await fetch(`${url}/api/meet`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    assert.equal(anon.status, 401);

    const viewer = await tokenFor(url, 'viewer');
    const forbidden = await fetch(`${url}/api/meet`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${viewer}` }, body: JSON.stringify(body) });
    assert.equal(forbidden.status, 403);

    const operator = await tokenFor(url, 'operator');
    const ok = await fetch(`${url}/api/meet`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` }, body: JSON.stringify(body) });
    assert.equal(ok.status, 200);
    const okBody = await ok.json();
    assert.equal(okBody.state.meets.seed, 99);
    assert.equal(okBody.state.meets.enabled, true);

    const dup = await fetch(`${url}/api/meet`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` }, body: JSON.stringify(body) });
    assert.equal(dup.status, 400);

    const bad = await fetch(`${url}/api/meet`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${operator}` }, body: JSON.stringify({ request_id: 'meet-2', seed: 'abc' }) });
    assert.equal(bad.status, 400);

    assert.ok(deps.audit.list().some((row) => row.action === 'MEET' && row.result === 'ACCEPTED'));
  });
});
