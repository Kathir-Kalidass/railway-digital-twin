# Windows GPU demo checklist

Educational simulation only; not certified railway equipment.

## Pre-flight

1. On the host, copy and tune the environment:
   ```powershell
   Copy-Item .env.sample .env
   ```
2. Generate broker credentials and start the stack:
   ```powershell
   ./scripts/dev-up.sh
   ```
3. Confirm the backend is ready: `curl http://localhost:3001/api/health` →
   `{"ok":true,"mqttConnected":true}`.
4. Open the dashboard at http://localhost:5173 and log in as `operator`.
5. If the ESP32 runs in Wokwi, expose the broker first
   (`cloudflared tunnel --url tcp://localhost:1883`) and follow
   `docs/wokwi-connectivity.md`.
6. Launch Godot 4.7 on the Windows GPU machine and open `godot/project.godot`.

## Run the checklist

| # | Check | Pass/Fail | Notes |
|---|---|---|---|
| a | Curved track renders and the train follows it without derailing | | |
| b | Train wheels rotate; follow camera stays stable | | |
| c | Cab camera can be selected and looks forward along the track | | |
| d | Wildlife spawns near the underpass and prefers crossing there | | |
| e | At least one animal crosses the track and triggers a detection | | |
| f | Safety sequence: warn → slow → stop with barrier down → clear → resume | | |
| g | ESP32 servo, buzzer, LEDs, and OLED match backend state | | |
| h | Dashboard shows the same signal, speed, and wildlife state | | |
| i | Reset is rejected while the hazard or sensor fault is active | | |
| j | Day/night cycle and cinematic reel render without artifacts | | |

## Observed values (fill during the run)

- Target speed during warning: ______ km/h
- Target speed during hazard: ______ km/h
- Target speed after reset/resume: ______ km/h
- MQTT client IDs seen by the broker: ______________________________

## Known limitations

- WSL has no GPU in this environment; run the checklist on the Windows host.
- “Stopping distance” is a visualization estimate, not certified braking.
