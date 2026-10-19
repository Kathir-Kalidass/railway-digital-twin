export function buildTopology(config) {
  const t = config.topology;
  const blocks = [];
  const lines = [];
  for (const line of t.lines) {
    const ids = [];
    for (let i = 0; i < t.blocksPerLine; i++) {
      const id = `${line}-B${i}`;
      blocks.push({ id, line, index: i, zone: t.zoneByIndex[i], lengthM: t.blockLengthM, occupiedBy: null });
      ids.push(id);
    }
    lines.push({ id: line, blocks: ids });
  }
  const station = { ...t.station, blocks: { UP: `UP-B${t.station.upIndex}`, DOWN: `DOWN-B${t.station.downIndex}` } };
  return { blocks, lines, station };
}

export function blockById(topology, id) {
  return topology.blocks.find((b) => b.id === id);
}

export function nextBlockId(topology, line, index) {
  const lineObj = topology.lines.find((l) => l.id === line);
  const n = lineObj.blocks.length;
  return `${line}-B${(index + 1) % n}`;
}
