import { config } from './src/config.js';
import { openDb } from './src/db.js';
import { makeAudit } from './src/audit.js';
import { makeReplay } from './src/replay.js';
import { makeAuth } from './src/auth.js';
import { makeState } from './src/state.js';
import { makeEvents } from './src/events.js';
import { makeBus } from './src/bus.js';
import { makeMqtt } from './src/mqtt.js';
import { makeIngest } from './src/ingest.js';
import { createApp } from './src/app.js';

const db = openDb(config.dbPath);
const audit = makeAudit(db);
const replay = makeReplay(db);
const auth = makeAuth({ db, config });
auth.seedUsers();
const state = makeState({ config });
state.setBrokerConnected(false); // fail-safe until the broker connection is established
const events = makeEvents();
let ingest;
const mqtt = makeMqtt({ config, onMessage: (topic, message) => ingest?.handle(topic, message) });
const bus = makeBus({ mqtt, state, events });
ingest = makeIngest({ state, bus, config });
mqtt.client.on('connect', () => {
  mqtt.subscribe(['railway/zone1/train', 'railway/zone1/wildlife', 'railway/zone2/train', 'railway/zone2/wildlife', 'railway/telemetry/esp32']);
  ingest.onBrokerConnected(true);
});
mqtt.client.on('close', () => ingest.onBrokerConnected(false));
const app = createApp({ config, db, audit, replay, auth, state, bus, events, mqtt });
app.listen(config.port, '0.0.0.0', () => console.log(`Railway backend listening on :${config.port}; MQTT=${config.mqttUrl}`));
