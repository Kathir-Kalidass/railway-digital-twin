import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildDeps, withServer, login } from './app_helpers.js';
import { config } from '../src/config.js';

test('wrong-line API enforces auth, RBAC and eligibility', async () => {
  const deps = buildDeps();
  await withServer(deps, async (url) => {
    const anon = await fetch(`${url}/api/routes/wrong-line`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ trainId: 'T1' }) });
    assert.equal(anon.status, 401);
    const viewer = (await login(url, 'viewer', config.seedUsers.find((u) => u.role === 'viewer').password)).body.token;
    assert.equal((await fetch(`${url}/api/routes/wrong-line`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${viewer}` }, body: JSON.stringify({ trainId: 'T1' }) })).status, 403);

    const operator = (await login(url, 'operator', config.seedUsers.find((u) => u.role === 'operator').password)).body.token;
    const read = await fetch(`${url}/api/routes/wrong-line`, { headers: { authorization: `Bearer ${operator}` } });
    assert.equal(read.status, 200);
    const body = await read.json();
    assert.ok(body.eligibility.T1);
    assert.equal(body.active, null);
  });
});
