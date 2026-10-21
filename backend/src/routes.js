import { blockById } from './railway.js';
import { isZoneRestrictive } from './signalling.js';
import { occupyBlocks } from './simulation.js';

export function makeRoutes({ topology, zones, trains, hasActiveHazard = () => false }) {
  const definitions = (topology.crossovers || []).map((r) => ({ ...r }));
  let active = null;
  let tickCount = 0;

  function list() {
    return definitions.map((d) => ({ ...d, active: active?.routeId === d.id }));
  }

  function activeRoute() {
    return active ? { ...active } : null;
  }

  function requestRoute({ trainId, routeId }) {
    if (active) return { ok: false, reason: `route ${active.routeId} busy` };
    const definition = definitions.find((d) => d.id === routeId);
    if (!definition) return { ok: false, reason: `unknown route ${routeId}` };
    const from = blockById(topology, definition.from);
    const to = blockById(topology, definition.to);
    if (!from || !to) return { ok: false, reason: 'route endpoint missing from topology' };
    if (isZoneRestrictive(zones[from.zone]) || isZoneRestrictive(zones[to.zone])) {
      return { ok: false, reason: 'route rejected: restrictive zone at endpoint' };
    }
    if (hasActiveHazard(from.id) || hasActiveHazard(to.id)) {
      return { ok: false, reason: 'route rejected: active hazard on route block' };
    }
    const train = trains.find((t) => t.id === trainId);
    if (!train) return { ok: false, reason: `unknown train ${trainId}` };
    if (train.block !== definition.from) return { ok: false, reason: `train ${trainId} is not at ${definition.from}` };
    occupyBlocks(topology, trains);
    if (to.occupiedBy && to.occupiedBy !== trainId) {
      return { ok: false, reason: `route rejected: ${to.id} occupied by ${to.occupiedBy}` };
    }
    active = { routeId, trainId, from: from.id, to: to.id, grantedAtTick: tickCount };
    train.line = to.line;
    train.block = to.id;
    train.offsetM = 0;
    occupyBlocks(topology, trains);
    return { ok: true, route: activeRoute() };
  }

  function tick() {
    tickCount += 1;
    if (!active) return null;
    const train = trains.find((t) => t.id === active.trainId);
    if (!train || train.block !== active.to) {
      const cleared = active;
      active = null;
      return cleared;
    }
    const destination = blockById(topology, active.to);
    if (destination && destination.occupiedBy !== active.trainId) {
      const cleared = active;
      active = null;
      return cleared;
    }
    return null;
  }

  return { list, requestRoute, tick, activeRoute };
}
