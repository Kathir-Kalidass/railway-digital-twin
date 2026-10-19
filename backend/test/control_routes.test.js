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
