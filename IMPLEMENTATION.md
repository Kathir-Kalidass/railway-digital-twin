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

## Important implementation details

- The train's speed response is intentionally a simple simulation profile. It does not model certified train dynamics, gradients, adhesion, signalling blocks, or real stopping distances.
- The dashboard's “Apply target speed” changes the backend state. The Godot simulation's local keyboard speed controls change its own target speed and report it. For a production-quality demo, centralize all speed commands in MQTT and have Godot subscribe to the same command stream through a dedicated adapter.
- `RESET` is rejected by the backend while a hazard or sensor fault is active. The ESP32 firmware likewise does not allow reset to override an active local hazard/fault input.
- The current development broker permits anonymous access and is intended for localhost-only demos. Do not expose it to the public internet.

## Troubleshooting

**Dashboard says backend unavailable**
- Run `docker compose ps` and `docker compose logs backend mqtt web`.
- Check `http://localhost:3001/api/health`.

**Godot doesn't update the dashboard**
- Ensure the backend is running on port 3001.
- If Godot is on another computer, change `API_BASE` in `main.gd` to the backend host address.
- The Godot simulation sends events to the backend over HTTP; the backend publishes the state/events over MQTT.

**ESP32 cannot connect to MQTT**
- Set `MQTT_HOST` to the broker's reachable LAN IP or your Wokwi-compatible broker endpoint. Never use `localhost` from ESP32.
- For physical hardware, allow TCP 1883 through the local firewall and ensure the broker listener accepts LAN clients.
- Wokwi networking depends on its current gateway support and network configuration; test broker reachability before the live demonstration.

**Godot is slow**
- Reduce `range(110)` in `_build_forest()` to `range(55)` and lower the window resolution.
