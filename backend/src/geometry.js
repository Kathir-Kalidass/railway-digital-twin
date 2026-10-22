const mod = (value, length) => ((value % length) + length) % length;

export function lineLength(topology, line) {
  const found = topology.lines.find((entry) => entry.id === line);
  if (!found) throw new Error(`unknown line ${line}`);
  return found.lengthM;
}

export function operationalToPhysical(topology, line, operational) {
  const length = lineLength(topology, line);
  const value = mod(Number(operational), length);
  return line === 'DOWN' ? mod(length - value, length) : value;
}

export function physicalToOperational(topology, line, physical) {
  return operationalToPhysical(topology, line, physical);
}

export function blockOffsetToPhysical(topology, line, blockId, offsetM) {
  const block = topology.blocks.find((entry) => entry.id === blockId);
  if (!block || block.line !== line) throw new Error(`unknown block ${blockId}`);
  return operationalToPhysical(topology, line, block.index * block.lengthM + Number(offsetM));
}

export function physicalToBlockOffset(topology, line, physical) {
  const length = lineLength(topology, line);
  const value = mod(Number(physical), length);
  const operational = line === 'DOWN' ? length - value : value;
  const lineObj = topology.lines.find((entry) => entry.id === line);
  const blockLength = length / lineObj.blocks.length;
  const index = Math.min(lineObj.blocks.length - 1, Math.floor(operational / blockLength));
  const blockId = lineObj.blocks[index];
  const block = topology.blocks.find((entry) => entry.id === blockId);
  return { blockId, offsetM: operational - block.index * block.lengthM };
}
