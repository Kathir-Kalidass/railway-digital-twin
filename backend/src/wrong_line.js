import { blockById } from './railway.js';
import { blockOffsetToPhysical, physicalToBlockOffset } from './geometry.js';
import { restoreSpeed } from './speed_restore.js';

const sectionBlockIds = (topology) => [topology.station.blocks.UP, topology.station.blocks.DOWN];
const mod = (v, n) => ((v % n) + n) % n;

export function makeWrongLine({ topology, trains, zones, config, hasActiveHazard = () => false, isMeetActive = () => false, onRestore = null }) {
  const cfg = config.wrongLine || {};
  const stationBlocks = sectionBlockIds(topology);
  const definitions = new Map((topology.crossovers || []).map((c) => [c.id, c]));
  const travelSign = (t) => Number.isFinite(t.travelSign) ? t.travelSign : (t.line === 'DOWN' ? -1 : 1);
  const lineLengthFor = (line) => topology.lines.find((l) => l.id === line).lengthM;
  const physicalOf = (t) => Number.isFinite(t.physicalM)
    ? mod(t.physicalM, lineLengthFor(t.line))
    : blockOffsetToPhysical(topology, t.line, t.block, t.offsetM);
  let active = null;
  let ticket = 0;
  let lastEvent = null;
  const history = [];

  function routeForLine(line) {
    return line === 'UP'
      ? { entry: definitions.get('X-A'), exit: definitions.get('X-B') }
      : { entry: definitions.get('X-B'), exit: definitions.get('X-A') };
  }

  function entryPhysicalFor(t) {
    const route = routeForLine(t.line);
    return route.entry?.atM ?? 0;
  }

  function opponentHoldPhysical(routeTrain, opponent, exitPhysical) {
    return exitPhysical - (cfg.holdBeforeEntryM || 0) * travelSign(opponent);
  }

  function restrictive(blockId) {
    const block = blockById(topology, blockId);
    const zone = block ? zones[block.zone] : null;
    return !zone || zone.wildlifeDetected || !zone.sensorHealthy || zone.status === 'RECOVERY_REQUIRED';
  }

  function sectionOccupant(trainId) {
    return stationBlocks.find((id) => {
      const block = blockById(topology, id);
      return block && block.occupiedBy && block.occupiedBy !== trainId;
    }) || null;
  }

  function evaluate(train) {
    const other = trains.find((t) => t.id !== train.id);
    const route = routeForLine(train.line);
    const entry = entryPhysicalFor(train);
    const exit = route.exit?.atM ?? entry;
    const distance = (entry - physicalOf(train)) * travelSign(train);
    const base = { eligible: false, reason: null, distanceToEntryM: Math.round(distance * 10) / 10 };
    if (!cfg.enabled) return { ...base, reason: 'disabled' };
    if (active) return { ...base, reason: 'route_busy' };
    if (isMeetActive()) return { ...base, reason: 'meet_active' };
    if (stationBlocks.some((id) => hasActiveHazard(id))) return { ...base, reason: 'hazard' };
    if (stationBlocks.some((id) => restrictive(id))) return { ...base, reason: 'restrictive_zone' };
    if (distance < (cfg.approachMinM || 0) || distance > (cfg.approachMaxM || 0)) return { ...base, reason: 'approach' };
    if (sectionOccupant(train.id)) return { ...base, reason: 'section_occupied' };
    if (!other) return { ...base, reason: 'opposing_missing' };
    const hold = opponentHoldPhysical(train, other, exit);
    const opponentDistance = (hold - physicalOf(other)) * travelSign(other);
    const stopM = Math.pow(Math.max(0, other.speedKmh) / 3.6, 2) / (2 * (config.simulation?.brakeMps2 || 2.0));
    if (opponentDistance < stopM + (cfg.stopMarginM || 0)) return { ...base, reason: 'opposing_too_close' };
    return { ...base, eligible: true, reason: null };
  }

  function eligibility() {
    return Object.fromEntries(trains.map((t) => [t.id, evaluate(t)]));
  }

  function setPhysical(train, line, physical) {
    const placed = physicalToBlockOffset(topology, line, physical);
    train.line = line;
    train.block = placed.blockId;
    train.offsetM = placed.offsetM;
    train.physicalM = mod(physical, lineLengthFor(line));
  }

  function opponentTransitSpeed(opponent) {
    if (Number.isFinite(active?.savedOpponentSpeed)) return active.savedOpponentSpeed;
    return zones[opponent.zone]?.targetSpeedKmh ?? opponent.targetSpeedKmh ?? opponent.speedKmh ?? 48;
  }

  function updateOpponentHold(opponent) {
    if (!Number.isFinite(active?.holdPhysicalM)) {
      opponent.commandedSpeedKmh = 0;
      return;
    }
    const distance = (active.holdPhysicalM - physicalOf(opponent)) * travelSign(opponent);
    if (distance <= 0) {
      opponent.commandedSpeedKmh = 0;
      return;
    }
    const speedMps = Math.max(0, opponent.speedKmh) / 3.6;
    const brake = config.simulation?.brakeMps2 || 2.0;
    const stopM = (speedMps * speedMps) / (2 * brake);
    opponent.commandedSpeedKmh = distance <= stopM + 2.0 ? 0 : active.opponentTransitSpeedKmh;
  }

  function reserve(on) {
    for (const id of stationBlocks) {
      const block = blockById(topology, id);
      if (block) block.reservedBy = on ? active.routeId : null;
    }
  }

  function finish(event) {
    if (!active) return null;
    const routeTrain = trains.find((t) => t.id === active.trainId);
    const opponent = trains.find((t) => t.id === active.heldTrainId);
    if (routeTrain) {
      restoreSpeed(routeTrain, active.savedRouteSpeed, {
        reason: 'WRONG_LINE_ROUTE_TRAIN',
        fallbackKmh: 48,
        onRestore,
      });
      routeTrain.routePhase = null;
      routeTrain.crossingProgress = 0;
      routeTrain.crossoverId = null;
    }
    if (opponent) {
      restoreSpeed(opponent, active.savedOpponentSpeed, {
        reason: event,
        fallbackKmh: 48,
        onRestore,
      });
    }
    reserve(false);
    history.push({ ...active, finishedAtTick: ticket, outcome: event });
    if (history.length > 10) history.shift();
    lastEvent = event;
    active = null;
    return event;
  }

  function request({ trainId }) {
    if (active) return { ok: false, reason: 'route_busy' };
    const train = trains.find((t) => t.id === trainId);
    if (!train) return { ok: false, reason: `unknown train ${trainId}` };
    const e = evaluate(train);
    if (!e.eligible) return { ok: false, reason: e.reason };
    const other = trains.find((t) => t.id !== trainId);
    const route = routeForLine(train.line);
    ticket += 1;
    active = {
      routeId: `WL-${trainId}-${ticket}`,
      trainId,
      heldTrainId: other.id,
      originalLine: train.line,
      destinationLine: train.line === 'UP' ? 'DOWN' : 'UP',
      entryCrossover: route.entry.id,
      exitCrossover: route.exit.id,
      entryPhysicalM: route.entry.atM,
      exitPhysicalM: route.exit.atM,
      holdPhysicalM: opponentHoldPhysical(train, other, route.exit.atM),
      phase: 'APPROACH',
      progress: 0,
      crossingProgress: 0,
      elapsedSec: 0,
      savedRouteSpeed: train.commandedSpeedKmh ?? null,
      savedOpponentSpeed: other.commandedSpeedKmh ?? null,
      opponentTransitSpeedKmh: null,
      operationalSign: train.operationalSign || 1,
    };
    active.opponentTransitSpeedKmh = opponentTransitSpeed(other);
    reserve(true);
    updateOpponentHold(other);
    train.commandedSpeedKmh = cfg.speedKmh;
    lastEvent = 'WRONG_LINE_GRANTED';
    return { ok: true, route: snapshot().active };
  }

  function beginEntry(train) {
    active.phase = 'CROSS_ENTRY';
    active.crossingProgress = 0;
    setPhysical(train, active.destinationLine, active.entryPhysicalM);
    train.operationalSign = -1;
    train.routePhase = 'CROSS_ENTRY';
  }

  function updateProgress() {
    if (!active) return 0;
    const weights = { APPROACH: 0.2, CROSS_ENTRY: 0.1, WRONG_LINE: 0.4, CROSS_EXIT: 0.1, CLEARANCE: 0.2 };
    const base = { APPROACH: 0, CROSS_ENTRY: 0.2, WRONG_LINE: 0.3, CROSS_EXIT: 0.7, CLEARANCE: 0.8, ABORTED_BLOCKED: 1 };
    let p = base[active.phase] ?? 0;
    if (active.phase === 'CROSS_ENTRY' || active.phase === 'CROSS_EXIT') p += weights[active.phase] * active.crossingProgress;
    if (active.phase === 'WRONG_LINE') {
      const total = Math.abs(active.exitPhysicalM - active.entryPhysicalM) - (cfg.crossingLengthM || 0) * 2;
      const done = Math.abs(physicalOf(trains.find((t) => t.id === active.trainId)) - active.entryPhysicalM) - (cfg.crossingLengthM || 0);
      p += weights.WRONG_LINE * Math.max(0, Math.min(1, done / Math.max(1, total)));
    }
    if (active.phase === 'CLEARANCE') {
      const t = trains.find((x) => x.id === active.trainId);
      const done = Math.abs(physicalOf(t) - active.exitPhysicalM);
      p += weights.CLEARANCE * Math.min(1, done / Math.max(1, t.lengthM));
    }
    return Math.max(0, Math.min(1, p));
  }

  function tick(dtSec) {
    const events = [];
    if (!active) return events;
    const train = trains.find((t) => t.id === active.trainId);
    const opponent = trains.find((t) => t.id === active.heldTrainId);
    if (!train || !opponent) { events.push(finish('WRONG_LINE_ABORTED')); return events; }
    active.elapsedSec = (active.elapsedSec || 0) + dtSec;
    updateOpponentHold(opponent);
    active.progress = updateProgress();

    if (stationBlocks.some((id) => hasActiveHazard(id))) {
      train.commandedSpeedKmh = 0;
      active.phase = 'ABORTED_BLOCKED';
      train.routePhase = 'ABORTED_BLOCKED';
      if (lastEvent !== 'WRONG_LINE_ABORTED_BLOCKED') {
        lastEvent = 'WRONG_LINE_ABORTED_BLOCKED';
        events.push(lastEvent);
      }
      return events;
    }

    if (active.phase === 'APPROACH') {
      const distance = (active.entryPhysicalM - physicalOf(train)) * travelSign(train);
      if (distance <= 0.5) beginEntry(train);
      if (active.elapsedSec > cfg.timeoutSec) {
        train.commandedSpeedKmh = 0;
        opponent.commandedSpeedKmh = 0;
        events.push(finish('WRONG_LINE_TIMEOUT'));
      }
      return events;
    }
    if (active.phase === 'ABORTED_BLOCKED') {
      events.push(finish('WRONG_LINE_ABORTED'));
      return events;
    }

    if (opponent && stationBlocks.includes(opponent.block)) {
      train.commandedSpeedKmh = 0;
      opponent.commandedSpeedKmh = 0;
      events.push(finish('WRONG_LINE_INTRUSION'));
      return events;
    }

    const speed = (cfg.speedKmh || 30) / 3.6;
    if (active.phase === 'CROSS_ENTRY') {
      active.crossingProgress = Math.min(1, active.crossingProgress + speed * dtSec / (cfg.crossingLengthM || 20));
      const physical = active.entryPhysicalM + travelSign(train) * (cfg.crossingLengthM || 20) * active.crossingProgress;
      setPhysical(train, active.destinationLine, physical);
      if (active.crossingProgress >= 1) {
        active.phase = 'WRONG_LINE';
        train.routePhase = 'WRONG_LINE';
      }
    } else if (active.phase === 'WRONG_LINE') {
      const exitStart = active.exitPhysicalM - travelSign(train) * (cfg.crossingLengthM || 20);
      const next = physicalOf(train) + travelSign(train) * speed * dtSec;
      if ((next - exitStart) * travelSign(train) >= 0) {
        setPhysical(train, active.destinationLine, exitStart);
        active.phase = 'CROSS_EXIT';
        active.crossingProgress = 0;
        train.routePhase = 'CROSS_EXIT';
      } else {
        setPhysical(train, active.destinationLine, next);
      }
    } else if (active.phase === 'CROSS_EXIT') {
      active.crossingProgress = Math.min(1, active.crossingProgress + speed * dtSec / (cfg.crossingLengthM || 20));
      const physical = active.exitPhysicalM - travelSign(train) * (cfg.crossingLengthM || 20) * (1 - active.crossingProgress);
      setPhysical(train, active.destinationLine, physical);
      if (active.crossingProgress >= 1) {
        setPhysical(train, active.originalLine, active.exitPhysicalM);
        train.operationalSign = 1;
        active.phase = 'CLEARANCE';
        train.routePhase = 'CLEARANCE';
      }
    } else if (active.phase === 'CLEARANCE') {
      const next = physicalOf(train) + travelSign(train) * speed * dtSec;
      setPhysical(train, active.originalLine, next);
      if ((physicalOf(train) - active.exitPhysicalM) * travelSign(train) >= train.lengthM) {
        events.push(finish('WRONG_LINE_COMPLETED'));
        return events;
      }
    }

    active.progress = updateProgress();
    return events;
  }

  function afterStep() {
    if (!active || active.phase !== 'APPROACH') return;
    const train = trains.find((t) => t.id === active.trainId);
    if (!train) return;
    const distance = (active.entryPhysicalM - physicalOf(train)) * travelSign(train);
    if (distance <= 0.5) beginEntry(train);
  }

  function cancel({ trainId }) {
    if (!active) return { ok: false, reason: 'no active route' };
    if (active.trainId !== trainId) return { ok: false, reason: 'train does not own route' };
    if (active.phase !== 'APPROACH') return { ok: false, reason: 'cancel only allowed during approach' };
    finish('WRONG_LINE_CANCELLED');
    return { ok: true };
  }

  function skipIds() {
    if (!active || active.phase === 'APPROACH') return [];
    return [active.trainId];
  }

  function snapshot() {
    return {
      active: active ? {
        trainId: active.trainId, routeId: active.routeId, phase: active.phase,
        entryCrossover: active.entryCrossover, exitCrossover: active.exitCrossover,
        progress: Math.round(active.progress * 1000) / 1000,
        crossingProgress: Math.round(active.crossingProgress * 1000) / 1000,
        heldTrainId: active.heldTrainId, holdPhysicalM: active.holdPhysicalM,
        elapsedSec: Math.round((active.elapsedSec || 0) * 1000) / 1000,
      } : null,
      eligibility: eligibility(),
      lastEvent,
      history: history.map((h) => ({ ...h })),
    };
  }

  return { request, cancel, tick, afterStep, snapshot, skipIds, eligibility, topology };
}
