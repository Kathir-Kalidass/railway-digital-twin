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
| b2 | Press `C` to cycle follow → cab → drone cameras | | |
| b3 | Press `N` to toggle day/night lighting | | |
| c | Cab camera can be selected and looks forward along the track | | |
| d | Wildlife spawns near the underpass and prefers crossing there | | |
| e | At least one animal crosses the track and triggers a detection | | |
| f | Safety sequence: warn → slow → stop with barrier down → clear → resume | | |
| g | ESP32 servo, buzzer, LEDs, and OLED match backend state | | |
| h | Dashboard shows the same signal, speed, and wildlife state | | |
| h2 | In-scene HUD shows zone, signal, wildlife, sensor, MQTT, speed and camera | | |
| i | Reset is rejected while the hazard or sensor fault is active | | |
| j | Day/night cycle and cinematic reel render without artifacts | | |
| j2 | Press `B` to run the cinematic reel (drone, dusk, then restore) | | |

## Observed values (fill during the run)

- Target speed during warning: ______ km/h
- Target speed during hazard: ______ km/h
- Target speed after reset/resume: ______ km/h
- MQTT client IDs seen by the broker: ______________________________

## WSL GPU validation record (2026-10-21)

Renderer: Mesa 25.2.8 D3D12 (`AMD Radeon(TM) Graphics` through WSLg) using
`gl_compatibility`, 1280x720, captured under `xvfb-run` to avoid WSLg window
buffer ghosting. The GPU path is forced with:

```bash
MESA_LOADER_DRIVER_OVERRIDE=d3d12 GALLIUM_DRIVER=d3d12 LIBGL_ALWAYS_SOFTWARE=0 \
  xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path godot --resolution 1280x720 --rendering-method gl_compatibility \
  --script res://tests/capture_scene.gd
```

| Check | Result |
|---|---|
| Curved track, LTS train placement, follow camera | PASS |
| Follow → cab → drone camera cycle | PASS |
| Day/night lighting, platform lamps, train lights | PASS |
| Cinematic reel (drone + dusk + restore) | PASS |
| HUD status/speed/camera text | PASS |
| Deer and elephant Blender models | PASS |
| In-scene wildlife crossing and safety barrier sequence | Covered by automated tests; not visually captured in WSL |
| Dashboard/ESP32/Wokwi end-to-end | Not part of WSL visual run |

The clean captures are development artifacts only. A 150-frame MovieWriter run
on this path reported about 11.8 ms GPU render time per frame (about 85 FPS at
1280x720 before encoding); the WSLg window without `xvfb-run` can leave stale
desktop content in captures, so always wrap capture runs with `xvfb-run`.

## Known limitations

- WSLg GPU validation covers rendering only; run the full checklist on the
  Windows host for dashboard, ESP32/Wokwi, and safety-sequence checks.
- “Stopping distance” is a visualization estimate, not certified braking.
