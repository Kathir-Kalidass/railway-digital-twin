import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildTopology } from '../src/railway.js';
import { makeRoutes } from '../src/routes.js';
import { occupyBlocks } from '../src/simulation.js';

const config = { zones: ['zone1', 'zone2'], topology: { lines: ['UP', 'DOWN'], blocksPerLine: 5, blockLengthM: 300, lineLengthM: { UP: 753.9822, DOWN: 728.8495 }, zoneByIndex: ['zone1', 'zone1', 'zone1', 'zone2', 'zone2'], station: { id: 'station', name: 'x', upIndex: 2, downIndex: 2, dwellSec: 20 }, crossovers: [
  { id: 'X-UP-DOWN', from: 'UP-B2', to: 'DOWN-B2' },
  { id: 'X-DOWN-UP', from: 'DOWN-B2', to: 'UP-B2' },
] } };
const makeTrain = (o = {}) => ({ id: 'T1', line: 'UP', direction: 'UP', block: 'UP-B2', offsetM: 0, speedKmh: 0, targetSpeedKmh: 48, lengthM: 60, status: 'RUNNING', zone: 'zone1', ...o });

function setup(extraTrains = []) {
  const topology = buildTopology(config);
  const zones = { zone1: { wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' }, zone2: { wildlifeDetected: false, sensorHealthy: true, status: 'NORMAL' } };
  const trains = [makeTrain(), makeTrain({ id: 'T3', line: 'DOWN', direction: 'DOWN', block: 'DOWN-B0', zone: 'zone1' }), ...extraTrains];
  occupyBlocks(topology, trains);
  const routes = makeRoutes({ topology, zones, trains });
  return { topology, zones, trains, routes };
}

test('grants a crossover and moves the train to the destination block', () => {
  const { trains, routes } = setup();
  const result = routes.requestRoute({ trainId: 'T1', routeId: 'X-UP-DOWN' });
  assert.equal(result.ok, true);
  assert.equal(trains[0].line, 'DOWN');
  assert.equal(trains[0].block, 'DOWN-B2');
  assert.equal(trains[0].offsetM, 0);
  assert.equal(routes.activeRoute().routeId, 'X-UP-DOWN');
});

test('rejects a second route while one is active', () => {
  const { routes } = setup();
  assert.equal(routes.requestRoute({ trainId: 'T1', routeId: 'X-UP-DOWN' }).ok, true);
  const second = routes.requestRoute({ trainId: 'T3', routeId: 'X-DOWN-UP' });
  assert.equal(second.ok, false);
  assert.match(second.reason, /busy|active/i);
});

test('rejects a route into an occupied block', () => {
  const blocker = makeTrain({ id: 'T9', line: 'DOWN', direction: 'DOWN', block: 'DOWN-B2', zone: 'zone1' });
  const { routes } = setup([blocker]);
  const result = routes.requestRoute({ trainId: 'T1', routeId: 'X-UP-DOWN' });
  assert.equal(result.ok, false);
  assert.match(result.reason, /occup/i);
});

test('rejects a route while a hazard affects either endpoint', () => {
  const { zones, routes } = setup();
  zones.zone1.wildlifeDetected = true;
  const result = routes.requestRoute({ trainId: 'T1', routeId: 'X-UP-DOWN' });
  assert.equal(result.ok, false);
  assert.match(result.reason, /hazard|restrict/i);
});

test('releases the route after the train clears the destination block', () => {
  const { trains, routes } = setup();
  routes.requestRoute({ trainId: 'T1', routeId: 'X-UP-DOWN' });
  trains[0].block = 'DOWN-B3';
  routes.tick();
  assert.equal(routes.activeRoute(), null);
  trains[1].block = 'DOWN-B2';
  const next = routes.requestRoute({ trainId: 'T3', routeId: 'X-DOWN-UP' });
  assert.equal(next.ok, true);
});

test('rejects unknown routes and trains', () => {
  const { routes } = setup();
  assert.equal(routes.requestRoute({ trainId: 'T1', routeId: 'NOPE' }).ok, false);
  assert.equal(routes.requestRoute({ trainId: 'NOPE', routeId: 'X-UP-DOWN' }).ok, false);
});
