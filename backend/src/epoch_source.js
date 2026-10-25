// Publishes the backend's wall clock on a retained MQTT topic so devices
// without SNTP (gated networks, the Wokwi IoT Gateway) can derive a valid
// telemetry/command timestamp. Retained delivery means a device subscribes
// to railway/boot and immediately receives the last epoch.
export function makeEpochSource({ mqtt, onTimer = (fn, ms) => setInterval(fn, ms) } = {}) {
  function publishEpoch() {
    mqtt.publish('railway/boot', { event: 'BROKER_EPOCH', epochMs: Date.now(), source: 'backend' }, { retain: true });
  }
  publishEpoch(); // no-op until the MQTT client is connected; retried on the timer
  const timer = onTimer(() => publishEpoch(), 60_000);
  timer?.unref?.();
  return { publishEpoch, close: () => clearInterval(timer) };
}
