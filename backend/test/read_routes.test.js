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
