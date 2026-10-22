export function makeWildlifeCommands({ state, bus, config, mqtt }) {
  let mode = 'NONE';
  let seq = 0;

  function publish(event, payload) {
    seq += 1;
    const cmd = {
      request_id: `backend-wildlife-${Date.now()}-${seq}`,
      zone: config.esp32Zone || config.zones[0],
      event,
      timestamp: new Date().toISOString(),
      source: 'backend',
      payload,
    };
    if (bus.command) bus.command('esp32', cmd);
    else if (mqtt) mqtt.publish('railway/commands/esp32', cmd);
    return cmd;
  }

  function sync() {
    const zone = config.esp32Zone || config.zones[0];
    const hazards = Object.values(state.getBlockHazards()).filter((h) => h.zone === zone && h.active);
    const confirmed = hazards.find((h) => h.stage === 'CONFIRMED') || null;
    const near = hazards.find((h) => h.stage === 'SUSPECTED') || null;
    const desired = confirmed ? 'DETECTED' : near ? 'NEAR' : 'NONE';
    if (desired === mode) return null;
    const previous = mode;
    mode = desired;
    const hazard = confirmed || near;
    if (!hazard) {
      if (previous === 'NEAR') return publish('WILDLIFE_NEAR_CLEAR', { source: 'backend' });
      if (previous === 'DETECTED') return publish('WILDLIFE_CLEARED', { source: 'backend' });
      return null;
    }
    if (desired === 'DETECTED') {
      return publish('WILDLIFE_DETECTED', { blockId: hazard.blockId, line: hazard.line, source: 'backend' });
    }
    return publish('WILDLIFE_NEAR', { blockId: hazard.blockId, line: hazard.line, source: 'backend' });
  }

  return { sync, getMode: () => mode };
}
