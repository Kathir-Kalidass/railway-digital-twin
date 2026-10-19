# Implementation notes and demo sequence

## Demo sequence (about 3 minutes)

1. Start the stack and launch Godot.
2. Show normal state: green signal, clear wildlife sensor, healthy sensor.
3. Press **Space**. The elephant model appears, train target speed becomes zero, signal turns red, and the backend records a high-severity wildlife event.
4. Press **Space** again to report wildlife clear. The restrictive state remains until reset.
5. Press **R** to reset after hazard clear. Green signal returns.
6. Press **F** to simulate sensor fault. Signal stays restrictive; reset is rejected until sensor restoration.
7. Press **F**, then **R** to restore normal operation.
8. Use **Up/Down** to adjust target speed; the simulated train accelerates/decelerates gradually.
9. From the dashboard, inject the same events and review the event stream.

## Security & recovery

- **Authenticated Mosquitto:** `allow_anonymous false`. Credentials are automatically generated from environment variables via `scripts/mosquitto_setup.sh`.
- **Granular ACLs:** The backend is the sole publisher of `railway/commands/*`, `railway/speed/*`, `railway/state`, `railway/alerts`, and `railway/zone*/signal`. Clients like Godot and ESP32 only publish telemetry on their designated topics. The dashboard has read-only access.
- **Envelope Validation & Anti-Replay:** All incoming commands are validated against schema, timestamp freshness (within ±5 minutes), and deduplicated using a persistent SQLite replay registry (`processed_requests`).
- **Audit Trail:** Every control attempt—accepted, rejected, or forbidden—is recorded in SQLite (`audit`) with actor, role, zone, action, and timestamp.
- **Fail-Safe & Recovery Policy (`COMM_LOST`):** On MQTT broker disconnect, the system immediately applies a restrictive fail-safe state (`COMM_LOST`). When the connection is restored, the backend reconciles the state by publishing the retained state snapshot.
- **Recovery Requirement:** Reset commands are rejected if an active hazard or sensor fault is present. Normal operation can only resume once sensors are healthy, hazards are cleared, and an authorized operator/admin issues an explicit reset.

## Important implementation details

- The train's speed response is intentionally a simple simulation profile. It does not model certified train dynamics, gradients, adhesion, signalling blocks, or real stopping distances.
- The dashboard's “Apply target speed” changes the backend state. The Godot simulation's local keyboard speed controls change its own target speed and report it.
- `RESET` is rejected by the backend while a hazard or sensor fault is active. The ESP32 firmware likewise does not allow reset to override an active local hazard/fault input.

## Troubleshooting

**Dashboard says backend unavailable**
- Run `docker compose ps` and `docker compose logs backend mqtt web`.
- Check `http://localhost:3001/api/health`.

**Godot doesn't update the dashboard**
- Ensure the backend is running on port 3001.
- If Godot is on Windows or another computer, change `API_BASE` in `main.gd` to the backend host address.

**ESP32 cannot connect to MQTT**
- Set `MQTT_HOST` to the broker's reachable LAN IP. Never use `localhost` from ESP32.
- For physical hardware, allow TCP 1883 through the local firewall.
