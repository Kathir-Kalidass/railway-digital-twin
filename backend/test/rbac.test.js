import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hasPermission, requirePermission } from '../src/rbac.js';

test('role permission matrix', () => {
  assert.equal(hasPermission('viewer', 'state:read'), true);
  assert.equal(hasPermission('viewer', 'control:issue'), false);
  assert.equal(hasPermission('operator', 'control:issue'), true);
  assert.equal(hasPermission('operator', 'audit:read'), false);
  assert.equal(hasPermission('admin', 'audit:read'), true);
  assert.equal(hasPermission('operator', 'route:set'), true);
  assert.equal(hasPermission('viewer', 'route:set'), false);
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
