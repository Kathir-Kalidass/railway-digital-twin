import { isZoneRestrictive } from './signalling.js';

const clampSpeed = (v) => Math.max(0, Math.min(80, v));

export function occupyBlocks(topology, trains) {
  for (const b of topology.blocks) b.occupiedBy = null;
  for (const t of trains) {
    const line = topology.lines.find((l) => l.id === t.line);
    const n = line.blocks.length;
    let idx = line.blocks.indexOf(t.block);
    let remaining = t.lengthM;
    let first = true;
    while (remaining > 0) {
      const block = topology.blocks.find((b) => b.id === line.blocks[idx]);
      if (first) { block.occupiedBy = t.id; remaining -= block.lengthM - t.offsetM; first = false; }
      else { block.occupiedBy = t.id; remaining -= block.lengthM; }
      idx = (idx + 1) % n;
      if (remaining <= 0) break;
    }
  }
}

function permittedTarget({ topology, simulation, zones, aspects, t }) {
  const line = topology.lines.find((l) => l.id === t.line);
  const idx = line.blocks.indexOf(t.block);
  const nextId = line.blocks[(idx + 1) % line.blocks.length];
  const nextBlock = topology.blocks.find((b) => b.id === nextId);
  const zone = zones[t.zone];
  const base = t.commandedSpeedKmh != null ? t.commandedSpeedKmh : (zone ? zone.targetSpeedKmh : simulation.defaultTargetSpeedKmh);
  let target = base;
  const nextAspect = aspects ? aspects[nextId] : 'GREEN';
  const ownConsist = nextBlock && nextBlock.occupiedBy === t.id;
  if (nextAspect === 'RED' && !ownConsist) target = 0;
  else if (nextAspect === 'YELLOW') target = Math.min(target, simulation.cautionSpeedKmh);
  return target;
}

export function stepTrains({ topology, simulation, zones, trains, dtSec, aspects }) {
  for (const t of trains) {
    const line = topology.lines.find((l) => l.id === t.line);
    const block = topology.blocks.find((b) => b.id === t.block);
    t.zone = block.zone;
    const zone = zones[t.zone];
    if (zone && isZoneRestrictive(zone)) t.status = 'EMERGENCY';
    else if (t.status === 'EMERGENCY' && !(zone && isZoneRestrictive(zone))) t.status = 'DWELL';

    const target = t.status === 'EMERGENCY' ? 0 : permittedTarget({ topology, simulation, zones, aspects, t });
    t.targetSpeedKmh = clampSpeed(target);
    const rate = t.speedKmh > t.targetSpeedKmh ? simulation.brakeMps2 : simulation.accelMps2;
    const deltaKmh = rate * 3.6 * dtSec;
    t.speedKmh = clampSpeed(t.speedKmh < t.targetSpeedKmh ? Math.min(t.targetSpeedKmh, t.speedKmh + deltaKmh) : Math.max(t.targetSpeedKmh, t.speedKmh - deltaKmh));

    let advance = (t.speedKmh / 3.6) * dtSec;
    while (advance > 0) {
      const cur = topology.blocks.find((b) => b.id === t.block);
      const room = cur.lengthM - t.offsetM;
      const nextIdx = (cur.index + 1) % line.blocks.length;
      const nextId = line.blocks[nextIdx];
      const nextBlock = topology.blocks.find((b) => b.id === nextId);
      if (advance >= room && aspects && aspects[nextId] === 'RED' && nextBlock?.occupiedBy !== t.id) {
        t.offsetM = cur.lengthM;
        t.speedKmh = 0;
        break;
      }
      if (advance < room) { t.offsetM += advance; advance = 0; }
      else {
        advance -= room;
        t.block = nextId;
        t.offsetM = 0;
      }
    }
    occupyBlocks(topology, trains);
  }
  return trains;
}
