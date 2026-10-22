import { useEffect, useState } from 'react';
import { Activity, AlertTriangle, ArrowRightLeft, CheckCircle2, Clock3, Cpu, Gauge, Leaf, Radio, RotateCcw, ShieldAlert, TrainFront, Wifi, Zap } from 'lucide-react';

const API = import.meta.env.VITE_API_URL || 'http://localhost:3001';

type Train = {
  id: string;
  line: string;
  direction?: number;
  block: string;
  offsetM: number;
  speedKmh: number;
  targetSpeedKmh: number;
  lengthM?: number;
  status?: string;
  zone?: string;
  travelSign?: number;
  physicalM?: number;
  routePhase?: string | null;
  crossingProgress?: number;
  crossoverId?: string | null;
  targetLine?: string | null;
};

type WrongLineEligibility = {
  eligible: boolean;
  reason: string | null;
  distanceToEntryM: number;
};

type WrongLine = {
  active: null | {
    trainId: string;
    routeId: string;
    phase: string;
    progress: number;
    crossingProgress: number;
    entryCrossover: string;
    exitCrossover: string;
    heldTrainId: string;
  };
  eligibility: Record<string, WrongLineEligibility>;
  lastEvent?: string | null;
};

type Hazard = {
  stage: 'NONE' | 'SUSPECTED' | 'CONFIRMED';
  confirmed: boolean;
  confidence: number | null;
  sensorSources: string[];
  camera?: { trainId: string; species: string; confidence: number; at: string } | null;
  sources: string[];
  since?: string;
};

type Block = {
  id: string;
  line: string;
  index: number;
  zone: string;
  lengthM: number;
  occupiedBy: string | null;
  signal: string;
  hazard?: Hazard | null;
};

type CameraHealth = {
  ok: boolean;
  degraded?: boolean;
  ml?: { modelLoaded?: boolean; stub?: boolean; model?: string };
};

type Meet = {
  enabled: boolean;
  seed: number;
  phase: string;
  nextMeetInSec: number;
  active?: {
    holderId?: string;
    otherId?: string;
    crossover?: boolean;
    routeId?: string | null;
  } | null;
  last?: {
    outcome?: string;
    holderId?: string;
    routeId?: string | null;
  } | null;
};

type State = {
  zone: string;
  signal: string;
  speedKmh: number;
  targetSpeedKmh: number;
  wildlifeDetected: boolean;
  sensorHealthy: boolean;
  barrier: string;
  status: string;
  stoppingDistanceM: number;
  lastEvent: string;
  updatedAt: string;
  mqttConnected: boolean;
  trains?: Train[];
  blocks?: Block[];
  routes?: {
    active?: { routeId: string; trainId: string; from: string; to: string } | null;
    wrongLine?: WrongLine;
  };
  meets?: Meet | null;
  zones?: Record<string, { esp32NearAnimal?: boolean }>;
};

type EventRow = {
  id: string;
  time: string;
  type: string;
  message?: string;
  severity?: string;
  zone?: string;
  source?: string;
};

const initial: State = {
  zone: 'ZONE_1',
  signal: 'GREEN',
  speedKmh: 48,
  targetSpeedKmh: 48,
  wildlifeDetected: false,
  sensorHealthy: true,
  barrier: 'OPEN',
  status: 'CONNECTING',
  stoppingDistanceM: 0,
  lastEvent: 'Waiting for backend',
  updatedAt: new Date().toISOString(),
  mqttConnected: false,
  trains: [
    { id: 'T1', line: 'UP', block: 'UP-B0', offsetM: 40, speedKmh: 48, targetSpeedKmh: 48, status: 'RUNNING' },
    { id: 'T3', line: 'DOWN', block: 'DOWN-B0', offsetM: 20, speedKmh: 45, targetSpeedKmh: 45, status: 'RUNNING' }
  ],
  blocks: [
    { id: 'UP-B0', line: 'UP', index: 0, zone: 'zone1', lengthM: 150.8, occupiedBy: 'T1', signal: 'RED' },
    { id: 'UP-B1', line: 'UP', index: 1, zone: 'zone1', lengthM: 150.8, occupiedBy: null, signal: 'GREEN' },
    { id: 'UP-B2', line: 'UP', index: 2, zone: 'zone1', lengthM: 150.8, occupiedBy: null, signal: 'GREEN' },
    { id: 'UP-B3', line: 'UP', index: 3, zone: 'zone2', lengthM: 150.8, occupiedBy: null, signal: 'GREEN' },
    { id: 'UP-B4', line: 'UP', index: 4, zone: 'zone2', lengthM: 150.8, occupiedBy: null, signal: 'GREEN' },
    { id: 'DOWN-B0', line: 'DOWN', index: 0, zone: 'zone1', lengthM: 145.8, occupiedBy: 'T3', signal: 'RED' },
    { id: 'DOWN-B1', line: 'DOWN', index: 1, zone: 'zone1', lengthM: 145.8, occupiedBy: null, signal: 'GREEN' },
    { id: 'DOWN-B2', line: 'DOWN', index: 2, zone: 'zone1', lengthM: 145.8, occupiedBy: null, signal: 'GREEN' },
    { id: 'DOWN-B3', line: 'DOWN', index: 3, zone: 'zone2', lengthM: 145.8, occupiedBy: null, signal: 'GREEN' },
    { id: 'DOWN-B4', line: 'DOWN', index: 4, zone: 'zone2', lengthM: 145.8, occupiedBy: null, signal: 'GREEN' }
  ]
};

function App() {
  const [state, setState] = useState<State>(initial);
  const [events, setEvents] = useState<EventRow[]>([]);
  const [cameraHealth, setCameraHealth] = useState<CameraHealth | null>(null);
  const [selectedTrain, setSelectedTrain] = useState<string>('T1');
  const [speed, setSpeed] = useState(48);
  const [error, setError] = useState('');
  const [token, setToken] = useState<string>(() => localStorage.getItem('railway_token') || '');
  const [username, setUsername] = useState('operator');
  const [password, setPassword] = useState('operator-dev-pass');

  async function api(path: string, body?: unknown) {
    const r = await fetch(`${API}${path}`, {
      method: body ? 'POST' : 'GET',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (!r.ok) {
      const err = await r.json().catch(() => ({}));
      throw new Error(err.reason || err.error || 'Request failed');
    }
    return r.json();
  }

  async function login() {
    try {
      const r = await fetch(`${API}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      });
      if (!r.ok) throw new Error('Login failed');
      const body = await r.json();
      localStorage.setItem('railway_token', body.token);
      setToken(body.token);
      setError('');
    } catch (e) {
      setError(String(e));
    }
  }

  async function refresh() {
    if (!token) return;
    try {
      const s = await api('/api/state');
      setState(s);
      if (s.trains && s.trains.length > 0) {
        const found = s.trains.find((t: Train) => t.id === selectedTrain);
        if (found) {
          setSpeed(found.targetSpeedKmh);
        }
      } else {
        setSpeed(s.targetSpeedKmh);
      }
      setEvents(await api('/api/events'));
      try {
        setCameraHealth(await api('/api/wildlife/camera/health'));
      } catch {
        setCameraHealth(null);
      }
      setError('');
    } catch {
      setError('Backend unavailable — start the Docker Compose services.');
    }
  }

  useEffect(() => {
    if (!token) return;
    refresh();
    const id = setInterval(refresh, 1500);
    return () => clearInterval(id);
  }, [selectedTrain, token]);

  async function command(event: string) {
    try {
      await api('/api/control', {
        request_id: crypto.randomUUID(),
        zone: 'zone1',
        event,
        timestamp: new Date().toISOString(),
        source: 'dashboard',
        payload: {},
      });
      await refresh();
    } catch (e) {
      setError(String(e));
    }
  }

  async function setTarget() {
    try {
      await api('/api/speed', { trainId: selectedTrain, speedKmh: speed });
      await refresh();
    } catch (e) {
      setError(String(e));
    }
  }

  async function requestWrongLine(trainId: string) {
    try {
      await api('/api/routes/wrong-line', { request_id: crypto.randomUUID(), trainId });
      await refresh();
    } catch (e) {
      setError(String(e));
    }
  }

  async function cancelWrongLine(trainId: string) {
    try {
      await api('/api/routes/wrong-line/cancel', { request_id: crypto.randomUUID(), trainId });
      await refresh();
    } catch (e) {
      setError(String(e));
    }
  }

  const trains = state.trains || [];
  const blocks = state.blocks || [];
  const activeHazard = blocks.find(b => b.hazard)?.hazard || null;
  const hazard = state.wildlifeDetected || !state.sensorHealthy || activeHazard != null;
  const activeTrain = trains.find(t => t.id === selectedTrain) || trains[0];
  const nearAnimal = state.zones?.[activeTrain?.zone || 'zone1']?.esp32NearAnimal === true;
  const meet = state.meets;
  const wrongLine = state.routes?.wrongLine;
  const wrongActive = wrongLine?.active || null;
  const wrongEligibility = wrongLine?.eligibility?.[selectedTrain];

  if (!token) {
    return (
      <main className="login-shell">
        <section className="login-panel">
          <div className="brandicon"><TrainFront size={24} /></div>
          <div className="eyebrow">DIGITAL TWIN / SAFETY SYSTEMS</div>
          <h1>Operator sign-in</h1>
          <p>Authenticate to supervise routes, fleet speed and wildlife fail-safe controls.</p>
          {error && <div className="error"><AlertTriangle size={17} />{error}</div>}
          <label className="field">Username<input value={username} onChange={e => setUsername(e.target.value)} autoComplete="username" /></label>
          <label className="field">Password<input type="password" value={password} onChange={e => setPassword(e.target.value)} autoComplete="current-password" /></label>
          <button className="primary full" onClick={login}>Sign in</button>
        </section>
      </main>
    );
  }

  return (
    <main className="shell">
      <header className="topbar">
        <div className="brand">
          <div className="brandicon"><TrainFront size={22} /></div>
          <div>
            <div className="eyebrow">DIGITAL TWIN / SAFETY SYSTEMS</div>
            <h1>Double-Track Railway Operations</h1>
          </div>
        </div>
        <div className="topmeta">
          <span className={`pill ${state.mqttConnected ? 'ok' : 'warn'}`}>
            <span className="dot" />
            {state.mqttConnected ? 'MQTT CONNECTED' : 'MQTT DISCONNECTED'}
          </span>
          <span className="clock">
            <Clock3 size={14} />
            {new Date(state.updatedAt).toLocaleTimeString()}
          </span>
        </div>
      </header>

      {error && <div className="error"><AlertTriangle size={17} />{error}</div>}

      <section className="hero">
        <div className="hero-copy">
          <div className="live"><span className="live-dot" /> LIVE FLEET & SIGNALLING</div>
          <h2>Multi-Train<br /><em>Double-Track Twin.</em></h2>
          <p>Supervise authoritative meet/pass block signalling, station crossover routing, and wildlife fail-safe protection across concentric UP & DOWN running lines.</p>
          <div className="hero-actions">
            <button className="primary" onClick={() => command('WILDLIFE_DETECTED')}><Leaf size={16} /> Inject wildlife event</button>
            <button className="secondary" onClick={() => command('SENSOR_FAULT')}><ShieldAlert size={16} /> Simulate sensor fault</button>
          </div>
        </div>
        <div className="hero-scene">
          <div className="sun" />
          <div className="mountain m1" />
          <div className="mountain m2" />
          <div className="forest f1">♠ ♠ ♠ ♠ ♠</div>
          <div className="forest f2">♠ ♠ ♠ ♠ ♠ ♠</div>
          <div className="rail rail1" />
          <div className="rail rail2" />
          <div className="sleepers" />
          <div className="train"><div className="train-window" /><div className="train-light" /></div>
          <div className={`signal ${state.signal.toLowerCase()}`}><i /><i /><i /></div>
          <div className={`hazard-marker ${hazard ? 'visible' : ''}`}>WILDLIFE ZONE</div>
          <div className="scene-label">
            <span>DOUBLE TRACK</span>
            <b>UP & DOWN CORRIDOR</b>
          </div>
        </div>
      </section>

      {/* Fleet Summary Cards */}
      <section className="fleet-grid">
        {trains.map(t => (
          <div
            key={t.id}
            className={`train-card ${t.id === selectedTrain ? 'selected' : ''}`}
            onClick={() => { setSelectedTrain(t.id); setSpeed(t.targetSpeedKmh); }}
          >
            <div className="train-card-head">
              <span className="train-badge"><TrainFront size={14} /> {t.id}</span>
              <span className={`line-pill ${t.line.toLowerCase()}`}>{t.line} LINE</span>
              <span className="train-status">{t.status || 'RUNNING'}</span>
            </div>
            <div className="train-metrics">
              <div><small>Current Speed</small><b>{t.speedKmh} <small>km/h</small></b></div>
              <div><small>Target Speed</small><b>{t.targetSpeedKmh} <small>km/h</small></b></div>
              <div><small>Block</small><b>{t.block}</b></div>
            </div>
            <div className="train-direction">{t.travelSign === -1 ? 'ANTICLOCKWISE' : 'CLOCKWISE'}</div>
          </div>
        ))}
      </section>

      {meet && (
        <section className="panel meet-panel">
          <div className="panel-head">
            <div>
              <div className="eyebrow">RANDOMISED MEETS</div>
              <h3>Station Hold Scheduler</h3>
            </div>
            <ArrowRightLeft size={19} />
          </div>
          <div className="meet-grid">
            <div><small>Phase</small><b>{meet.enabled ? meet.phase : 'DISABLED'}</b></div>
            <div><small>Next meet</small><b>{meet.phase === 'IDLE' ? `${Math.ceil(meet.nextMeetInSec)} s` : 'ACTIVE'}</b></div>
            <div><small>Holder</small><b>{meet.active?.holderId || '—'}</b></div>
            <div><small>Other train</small><b>{meet.active?.otherId || '—'}</b></div>
            <div><small>Seed</small><b>{meet.seed}</b></div>
            <div><small>Last outcome</small><b>{meet.last?.outcome || '—'}</b></div>
          </div>
        </section>
      )}

      {wrongLine && (
        <section className="panel route-panel">
          <div className="panel-head">
            <div>
              <div className="eyebrow">INTERLOCKED ROUTE</div>
              <h3>Wrong-Line Run</h3>
            </div>
            <ArrowRightLeft size={19} />
          </div>
          <div className="route-grid">
            <div><small>Train</small><b>{wrongActive?.trainId || selectedTrain}</b></div>
            <div><small>Eligibility</small><b>{wrongEligibility?.eligible ? 'READY' : (wrongEligibility?.reason?.replaceAll('_', ' ') || 'UNKNOWN')}</b></div>
            <div><small>Distance to entry</small><b>{wrongEligibility?.distanceToEntryM ?? '—'} m</b></div>
            <div><small>Phase</small><b>{wrongActive?.phase || 'IDLE'}</b></div>
            <div><small>Progress</small><b>{wrongActive ? `${Math.round(wrongActive.progress * 100)}%` : '—'}</b></div>
            <div><small>Held</small><b>{wrongActive?.heldTrainId || '—'}</b></div>
          </div>
          <div className="route-actions">
            <button className="primary" disabled={!wrongEligibility?.eligible || !!wrongActive} onClick={() => requestWrongLine(selectedTrain)}>
              Start wrong-line run
            </button>
            <button
              className="secondary"
              disabled={!wrongActive || wrongActive.phase !== 'APPROACH' || wrongActive.trainId !== selectedTrain}
              onClick={() => cancelWrongLine(wrongActive?.trainId || selectedTrain)}
            >
              Cancel approach
            </button>
          </div>
          <p className="route-note">Interlocked wrong-line: X-A entry / X-B exit. The opposing train is held clear of the station section.</p>
        </section>
      )}

      <section className="panel wildlife-panel">
        <div className="panel-head">
          <div>
            <div className="eyebrow">WILDLIFE SAFETY</div>
            <h3>Sensor → Camera → Stop</h3>
          </div>
          <Leaf size={19} />
        </div>
        <div className="wildlife-grid">
          <div><small>Stage</small><b>{activeHazard?.stage || 'NONE'}</b></div>
          <div><small>Sources</small><b>{activeHazard?.sensorSources?.join(' + ') || '—'}</b></div>
          <div><small>Confidence</small><b>{activeHazard?.confidence?.toFixed(2) ?? '—'}</b></div>
          <div><small>Species</small><b>{activeHazard?.camera?.species || '—'}</b></div>
          <div><small>Camera</small><b>{cameraHealth?.degraded ? 'DEGRADED' : cameraHealth?.ok ? 'ONLINE' : 'UNKNOWN'}</b></div>
          <div><small>ML</small><b>{cameraHealth?.ml?.modelLoaded ? (cameraHealth.ml.stub ? 'STUB' : 'LOADED') : 'UNAVAILABLE'}</b></div>
          <div><small>Near warning</small><b>{nearAnimal ? '30 km/h' : '—'}</b></div>
        </div>
      </section>

      {/* Block Signalling & Occupancy Diagram */}
      <section className="panel block-diagram-panel">
        <div className="panel-head">
          <div>
            <div className="eyebrow">TOPOLOGY & SIGNALLING</div>
            <h3>Authoritative Block Signalling & Occupancy</h3>
          </div>
          <Radio size={19} />
        </div>

        <div className="block-lines">
          {['UP', 'DOWN'].map(lineId => {
            const lineBlocks = blocks.filter(b => b.line === lineId);
            return (
              <div key={lineId} className="line-row">
                <span className="line-tag">{lineId}</span>
                <div className="blocks-track">
                  {lineBlocks.map(b => {
                    const aspect = (b.signal || 'GREEN').toLowerCase();
                    return (
                      <div key={b.id} className={`block-cell ${b.occupiedBy ? 'occupied' : ''} ${b.hazard ? 'hazard' : ''}`}>
                        <div className="block-cell-head">
                          <span className="block-name">{b.id}</span>
                          <span className={`signal-light ${aspect}`} title={`Signal: ${b.signal}`} />
                        </div>
                        {b.occupiedBy && (
                          <span className="occupancy-pill">
                            <TrainFront size={10} /> {b.occupiedBy}
                          </span>
                        )}
                        {b.hazard && (
                          <span className="hazard-pill" title={`Sources: ${b.hazard.sources?.join(', ')}`}>
                            <Leaf size={10} /> {b.hazard.stage === 'CONFIRMED' ? 'CONFIRMED' : 'SUSPECTED'} {b.hazard.sensorSources?.map(s => s === 'trackside' ? 'HUT' : s === 'onboardSensor' ? 'CAM' : 'CAMERA').join('+')}
                          </span>
                        )}
                        {b.id.includes('B2') && <small className="station-hint">Station</small>}
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>

      </section>

      {/* System Metrics Grid */}
      <section className="metric-grid">
        <Metric
          icon={<Gauge />}
          label={`${selectedTrain} SPEED`}
          value={`${activeTrain?.speedKmh ?? state.speedKmh} km/h`}
          sub={`Target ${activeTrain?.targetSpeedKmh ?? state.targetSpeedKmh} km/h`}
          tone={hazard ? 'amber' : ''}
        />
        <Metric
          icon={<Radio />}
          label="ZONE SIGNAL"
          value={state.signal}
          sub="Authority supervisor"
          tone={state.signal === 'RED' ? 'red' : 'green'}
        />
        <Metric
          icon={<Leaf />}
          label="WILDLIFE SENSOR"
          value={state.wildlifeDetected ? 'INTRUSION' : 'CLEAR'}
          sub={state.wildlifeDetected ? 'Level crossing alert' : 'No intrusion reported'}
          tone={state.wildlifeDetected ? 'red' : 'green'}
        />
        <Metric
          icon={state.sensorHealthy ? <CheckCircle2 /> : <AlertTriangle />}
          label="SENSOR HEALTH"
          value={state.sensorHealthy ? 'HEALTHY' : 'FAULT'}
          sub="Trackside Channel 01"
          tone={state.sensorHealthy ? 'green' : 'red'}
        />
      </section>

      <section className="lower-grid">
        <div className="panel control-panel">
          <div className="panel-head">
            <div>
              <div className="eyebrow">CONTROL DESK</div>
              <h3>Fleet Speed & Hazard Controls</h3>
            </div>
            <Zap size={19} />
          </div>

          <div className="control-status">
            <span className={`status-icon ${hazard ? 'danger' : 'safe'}`}>
              {hazard ? <AlertTriangle size={19} /> : <CheckCircle2 size={19} />}
            </span>
            <div>
              <b>{state.status.replaceAll('_', ' ')}</b>
              <p>{hazard ? 'Restrictive state active; resolve hazard and send RESET.' : 'Simulation running within safe authority bounds.'}</p>
            </div>
          </div>

          <div className="slider-head">
            <label>Target speed for <strong>{selectedTrain}</strong></label>
            <strong>{speed} <small>km/h</small></strong>
          </div>
          <input
            type="range"
            min="0"
            max="80"
            step="4"
            value={speed}
            onChange={e => setSpeed(Number(e.target.value))}
          />
          <div className="range-labels">
            <span>0 km/h</span>
            <span>80 km/h</span>
          </div>
          <button className="primary full" onClick={setTarget}>Apply target speed to {selectedTrain}</button>

          <div className="button-row">
            <button className="secondary" onClick={() => command('WILDLIFE_CLEARED')}>Clear wildlife</button>
            <button className="secondary" onClick={() => command('SENSOR_RESTORED')}>Restore sensor</button>
          </div>
          <button className="reset" onClick={() => command('RESET')}>
            <RotateCcw size={15} /> Reset to normal <span>Only if safe</span>
          </button>
        </div>

        <div className="panel">
          <div className="panel-head">
            <div>
              <div className="eyebrow">EVENT STREAM</div>
              <h3>Audit & Operations Log</h3>
            </div>
            <Activity size={19} />
          </div>
          <div className="event-list">
            {events.length === 0 ? (
              <div className="empty">No events yet. Inject a scenario to begin.</div>
            ) : (
              events.slice(0, 7).map(e => (
                <div className="event" key={e.id}>
                  <div className={`event-icon ${e.severity === 'HIGH' || e.type.includes('FAULT') ? 'red' : ''}`}>
                    <AlertTriangle size={15} />
                  </div>
                  <div className="event-copy">
                    <b>{e.type.replaceAll('_', ' ')}</b>
                    <p>{e.message || e.source || 'Simulation event'}</p>
                    <time>{new Date(e.time).toLocaleTimeString()}</time>
                  </div>
                  <span className="event-source">{e.source || 'SYSTEM'}</span>
                </div>
              ))
            )}
          </div>
        </div>
      </section>

      <footer>
        <span><Cpu size={14} /> ESP32 controller integration</span>
        <span><Wifi size={14} /> MQTT bridge · Multi-Train Authority · Godot 4 Twin</span>
        <span className="disclaimer">EDUCATIONAL SIMULATION ONLY</span>
      </footer>
    </main>
  );
}

function Metric({ icon, label, value, sub, tone }: { icon: React.ReactNode; label: string; value: string; sub: string; tone: string }) {
  return (
    <div className="metric">
      <div className={`metric-icon ${tone}`}>{icon}</div>
      <div className="metric-label">{label}</div>
      <div className={`metric-value ${tone}`}>{value}</div>
      <div className="metric-sub">{sub}</div>
    </div>
  );
}

export default App;
