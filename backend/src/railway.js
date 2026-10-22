export function buildTopology(config) {
  const t = config.topology;
  const blocks = [];
  const lines = [];
  for (const line of t.lines) {
    const ids = [];
    const lineLengthM = t.lineLengthM?.[line] ?? t.blockLengthM * t.blocksPerLine;
    const blockLengthM = Math.round((lineLengthM / t.blocksPerLine) * 1000) / 1000;
    for (let i = 0; i < t.blocksPerLine; i++) {
      const id = `${line}-B${i}`;
      blocks.push({ id, line, index: i, zone: t.zoneByIndex[i], lengthM: blockLengthM, occupiedBy: null, reservedBy: null });
      ids.push(id);
    }
    lines.push({ id: line, blocks: ids, lengthM: lineLengthM });
  }
  const station = { ...t.station, blocks: { UP: `UP-B${t.station.upIndex}`, DOWN: `DOWN-B${t.station.downIndex}` } };
  const crossovers = (t.crossovers || []).map((route) => ({ ...route }));
  return { blocks, lines, station, crossovers };
}

export function blockById(topology, id) {
  return topology.blocks.find((b) => b.id === id);
}

export function nextBlockId(topology, line, index) {
  const lineObj = topology.lines.find((l) => l.id === line);
  const n = lineObj.blocks.length;
  return `${line}-B${(index + 1) % n}`;
}
