const ORDER = { GREEN: 0, YELLOW: 1, RED: 2 };

export function mostRestrictive(a, b) {
  return ORDER[a] >= ORDER[b] ? a : b;
}

export function isZoneRestrictive(z) {
  return Boolean(z.wildlifeDetected) || !z.sensorHealthy || z.status === 'RECOVERY_REQUIRED';
}

export function deriveBlockAspects({ topology, blocks, zones, blockHazards = {}, lookaheadBlocks = 2 }) {
  const byId = new Map(blocks.map((b) => [b.id, b]));
  const occupied = new Set(blocks.filter((b) => b.occupiedBy).map((b) => b.id));
  const aspects = {};
  for (const line of topology.lines) {
    const ids = line.blocks;
    const n = ids.length;
    for (let i = 0; i < n; i++) {
      const block = byId.get(ids[i]);
      let aspect = 'GREEN';
      if (occupied.has(block.id)) {
        aspect = 'RED';
      } else {
        let yellow = false;
        for (let k = 1; k <= lookaheadBlocks; k++) {
          if (occupied.has(ids[(i + k) % n])) { yellow = true; break; }
        }
        aspect = yellow ? 'YELLOW' : 'GREEN';
      }
      if (isZoneRestrictive(zones[block.zone])) aspect = mostRestrictive(aspect, 'RED');

      if (blockHazards[block.id]?.active) {
        aspect = mostRestrictive(aspect, 'RED');
      }
      for (let k = 1; k <= 1; k++) {
        const aheadId = ids[(i + k) % n];
        if (blockHazards[aheadId]?.active) {
          aspect = mostRestrictive(aspect, 'YELLOW');
          break;
        }
      }
      aspects[block.id] = aspect;
    }
  }
  return aspects;
}

export function zoneSignal(zoneId, zones, blockHazards = {}) {
  if (isZoneRestrictive(zones[zoneId])) return 'RED';
  const hasActiveHazardHere = Object.values(blockHazards).some((h) => h.zone === zoneId && h.active);
  if (hasActiveHazardHere) return 'YELLOW';
  const otherRestrictive = Object.keys(zones).some((id) => id !== zoneId && (isZoneRestrictive(zones[id]) || Object.values(blockHazards).some((h) => h.zone === id && h.active)));
  return otherRestrictive ? 'YELLOW' : 'GREEN';
}
