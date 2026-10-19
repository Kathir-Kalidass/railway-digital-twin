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
