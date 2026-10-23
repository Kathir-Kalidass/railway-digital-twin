import { validateWildlifeObservation } from './validate.js';
import { makeWildlifeCommands } from './wildlife_commands.js';

export function makeIngest({ state, bus, config, mqtt, commands = null, commandTracker = null }) {
  const seenTelemetryIds = new Set();
  const maxSeenTelemetryIds = 256;
  const telemetryMaxAgeMs = 5 * 60 * 1000;

  const seenWildlifeEventIds = new Set();
  const maxSeenWildlifeEventIds = 256;
  const wildlifeCommands = commands || makeWildlifeCommands({ state, bus, config, mqtt });

  function rejectTelemetry(reason) {
    state.markEvent('INVALID_TELEMETRY');
    bus.event({ type: 'INVALID_TELEMETRY', source: 'esp32', reason });
  }

  function rememberTelemetry(requestId) {
    seenTelemetryIds.add(requestId);
    if (seenTelemetryIds.size > maxSeenTelemetryIds) {
      seenTelemetryIds.delete(seenTelemetryIds.values().next().value);
    }
  }

  function rememberWildlifeEvent(eventId) {
    seenWildlifeEventIds.add(eventId);
    if (seenWildlifeEventIds.size > maxSeenWildlifeEventIds) {
      seenWildlifeEventIds.delete(seenWildlifeEventIds.values().next().value);
    }
  }

  function validEnvelope(message) {
    const expectedZone = config.esp32Zone || config.zones[0];
    const payload = message?.payload;
    const timestamp = Date.parse(message?.timestamp);
    if (!message || message.event !== 'DEVICE_TELEMETRY' || message.source !== 'esp32') return 'invalid envelope';
    if (message.zone !== expectedZone || !config.zones.includes(message.zone)) return 'invalid device zone';
    if (typeof message.request_id !== 'string' || !message.request_id) return 'request_id required';
    if (message.clockValid !== true || Number.isNaN(timestamp) || Math.abs(Date.now() - timestamp) > telemetryMaxAgeMs) return 'stale or clock-invalid timestamp';
    if (!payload || payload.device !== 'esp32' || typeof payload.sensorHealthy !== 'boolean') return 'invalid payload';
    if (Object.hasOwn(payload, 'wildlifeDetected') && typeof payload.wildlifeDetected !== 'boolean') return 'invalid wildlife value';
    if (Object.hasOwn(payload, 'nearAnimal') && typeof payload.nearAnimal !== 'boolean') return 'invalid near-animal value';
    if (Object.hasOwn(payload, 'uptimeMs') && (!Number.isFinite(payload.uptimeMs) || payload.uptimeMs < 0)) return 'invalid uptime';
    if (seenTelemetryIds.has(message.request_id)) return 'duplicate request_id';
    return null;
  }

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
    if (topic === 'railway/wildlife') {
      const valid = validateWildlifeObservation(message, config);
      if (!valid.ok) {
        state.markEvent('INVALID_WILDLIFE');
        bus.event({ type: 'INVALID_WILDLIFE', source: message?.source || 'unknown', reason: valid.reason });
        return;
      }
      if (seenWildlifeEventIds.has(valid.value.eventId)) {
        return; // drop duplicate observation
      }
      rememberWildlifeEvent(valid.value.eventId);

      const applied = state.applyWildlifeObservation(valid.value);
      if (!applied.ok) {
        return;
      }

      wildlifeCommands.sync();
      bus.snapshot();
      return;
    }
    if (topic === 'railway/telemetry/esp32') {
      if (message.event === 'DEVICE_TELEMETRY') {
        const invalid = validEnvelope(message);
        if (invalid) {
          rejectTelemetry(invalid);
          return;
        }
        state.markEsp32Telemetry(message.zone);
        state.setSensor(message.zone, message.payload.sensorHealthy);
        if (typeof message.payload.wildlifeDetected === 'boolean') {
          state.setWildlife(message.zone, message.payload.wildlifeDetected);
        }
        if (typeof message.payload.nearAnimal === 'boolean') {
          state.setEsp32NearAnimal(message.zone, message.payload.nearAnimal);
        }
        rememberTelemetry(message.request_id);
        // Fresh valid telemetry is the device's response; publishes alone never ack a command.
        commandTracker?.acknowledgePending(Date.now());
        if (message.payload.sensorHealthy === false) {
          bus.alert({ source: 'esp32', severity: 'HIGH', message: 'ESP32 reports sensor fault', timestamp: new Date().toISOString() });
        }
        bus.snapshot();
        return;
      }

      // Temporary migration path for the previously emitted flat payload.
      const expectedZone = config.esp32Zone || config.zones[0];
      const zone = message.zone || expectedZone;
      if (message.device !== 'esp32' || zone !== expectedZone || typeof message.sensorHealthy !== 'boolean') {
        rejectTelemetry('invalid legacy telemetry');
        return;
      }
      state.markEsp32Telemetry(zone);
      state.setSensor(zone, message.sensorHealthy);
      if (typeof message.wildlifeDetected === 'boolean') state.setWildlife(zone, message.wildlifeDetected);
      commandTracker?.acknowledgePending(Date.now());
      if (message.sensorHealthy === false) {
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

  return { handle, onBrokerConnected, commands: wildlifeCommands };
}
