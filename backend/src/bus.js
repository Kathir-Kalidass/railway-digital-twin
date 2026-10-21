export function makeBus({ mqtt, state, events }) {
  return {
    snapshot() {
      const s = state.snapshot();
      mqtt.publish('railway/state', s, { retain: true });
      for (const id of Object.keys(s.zones)) {
        mqtt.publish(`railway/${id}/signal`, { zone: id, signal: s.zones[id].signal, timestamp: s.updatedAt }, { retain: true });
      }
      for (const b of s.blocks || []) {
        mqtt.publish(`railway/signal/${b.id}`, { block: b.id, line: b.line, zone: b.zone, signal: b.signal || 'GREEN', occupiedBy: b.occupiedBy || null, timestamp: s.updatedAt }, { retain: true });
      }
      return s;
    },
    event(e) {
      const entry = events.record(e);
      mqtt.publish('railway/events', entry);
      return entry;
    },
    alert(a) { mqtt.publish('railway/alerts', a); },
    security(e) { mqtt.publish('railway/security/events', e); },
  };
}
