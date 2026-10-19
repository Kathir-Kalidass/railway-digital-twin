import mqtt from 'mqtt';

export function makeMqtt({ config, onMessage }) {
  const client = mqtt.connect(config.mqttUrl, {
    username: config.mqttUser,
    password: config.mqttPass,
    reconnectPeriod: 2000,
    connectTimeout: 5000,
    clientId: `backend-${Math.random().toString(16).slice(2, 8)}`,
  });
  client.on('message', (topic, buffer) => {
    try { onMessage?.(topic, JSON.parse(buffer.toString())); }
    catch { onMessage?.(topic, { _raw: buffer.toString() }); }
  });
  return {
    client,
    publish(topic, obj, { retain = false } = {}) {
      if (client.connected) client.publish(topic, JSON.stringify(obj), { qos: 0, retain });
    },
    subscribe(topics) {
      client.subscribe(topics, { qos: 0 });
    },
    isConnected() { return client.connected; },
    close() { client.end(true); },
  };
}
