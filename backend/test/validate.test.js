import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateCommand, validateRoute, validateSpeed } from '../src/validate.js';

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

test('validateSpeed accepts a known trainId and rejects unknown ones', () => {
  const trainIds = ['T1', 'T3'];
  assert.equal(validateSpeed({ trainId: 'T1', speedKmh: 30 }, { zones, trainIds }).ok, true);
  assert.equal(validateSpeed({ trainId: 'NOPE', speedKmh: 30 }, { zones, trainIds }).ok, false);
  assert.equal(validateSpeed({ trainId: 'T1', speedKmh: 200 }, { zones, trainIds }).ok, false);
});

test('validateRoute accepts a known train and route, rejects unknown ids', () => {
  const trainIds = ['T1', 'T3'];
  const routeIds = ['X-UP-DOWN', 'X-DOWN-UP'];
  assert.equal(validateRoute({ request_id: 'r1', trainId: 'T1', routeId: 'X-UP-DOWN' }, { trainIds, routeIds }).ok, true);
  assert.equal(validateRoute({ request_id: '', trainId: 'T1', routeId: 'X-UP-DOWN' }, { trainIds, routeIds }).ok, false);
  assert.equal(validateRoute({ request_id: 'r2', trainId: 'NOPE', routeId: 'X-UP-DOWN' }, { trainIds, routeIds }).ok, false);
  assert.equal(validateRoute({ request_id: 'r3', trainId: 'T1', routeId: 'NOPE' }, { trainIds, routeIds }).ok, false);
});

import { validateMeet } from '../src/validate.js';

test('validateMeet accepts toggles, seeds and triggers', () => {
  assert.equal(validateMeet({ request_id: 'm1', enabled: true }).ok, true);
  assert.equal(validateMeet({ request_id: 'm2', seed: 42 }).ok, true);
  assert.equal(validateMeet({ request_id: 'm3', trigger: true }).ok, true);
});

test('validateMeet rejects missing ids and bad types', () => {
  assert.equal(validateMeet({ enabled: true }).ok, false);
  assert.equal(validateMeet({ request_id: 'm4', enabled: 'yes' }).ok, false);
  assert.equal(validateMeet({ request_id: 'm5', seed: 'abc' }).ok, false);
  assert.equal(validateMeet({ request_id: 'm6', trigger: 1 }).ok, false);
});
