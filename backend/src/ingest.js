export function makeIngest({ state, bus, config }) {
  let esp32Online = false;

  function handle(topic, message = {}) {
    const zoneMatch = topic.match(/^railway\/(zone\d+)\/(train|wildlife)$/);
    if (zoneMatch) {
      const [, zone, kind] = zoneMatch;
      if (!config.zones.includes(zone)) return;
      if (kind === 'train') state.applyTelemetry(zone, { trainPresent: message.trainPresent, speedKmh: message.speedKmh });
      else state.applyTelemetry(zone, { wildlifeDetected: message.wildlifeDetected });
      bus.snapshot();
      return;
    }
    if (topic === 'railway/telemetry/esp32') {
      esp32Online = true;
      if (message.sensorHealthy === false) {
        for (const id of config.zones) state.applyTelemetry(id, { sensorHealthy: false });
        bus.alert({ source: 'esp32', severity: 'HIGH', message: 'ESP32 reports sensor fault', timestamp: new Date().toISOString() });
      }
      bus.snapshot();
      return;
    }
    bus.event({ type: 'INVALID_TOPIC', topic });
  }

  function onBrokerConnected(connected) {
    state.setBrokerConnected(connected);
    if (connected) {
      bus.event({ type: 'BROKER_CONNECTED', message: 'Reconciling state from authoritative snapshot.' });
      bus.snapshot();
    } else {
      bus.event({ type: 'BROKER_DISCONNECTED', message: 'Communication lost; restrictive state applied.' });
      bus.snapshot();
    }
  }

  return { handle, onBrokerConnected };
}
