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
