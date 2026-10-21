# Wokwi to broker connectivity

Wokwi simulations run in the cloud. The virtual ESP32 uses the `Wokwi-GUEST`
WiFi network and can only reach hosts that are reachable from the public
internet; `localhost` always refers to the Wokwi container, not your machine.

## Option 0: Wokwi for VS Code (private gateway)

The VS Code extension bundles the Wokwi Private IoT Gateway, which joins the
simulated ESP32 to your machine's network. Enable it once with
`F1 → Enable Private Wokwi IoT Gateway`, then point the firmware at the host
under the name Wokwi provides:

```c
#define MQTT_HOST "host.wokwi.internal"
#define MQTT_PORT 1883
```

Open the `esp32/` folder as the VS Code workspace so Wokwi finds
`wokwi.toml` and `diagram.json`. `esp32/wokwi.toml` points at the PlatformIO
build output (`.pio/build/esp32dev/firmware.bin`). Wokwi does not compile the
sketch: build first with `pio run -e esp32dev` (the first build downloads the
ESP32 toolchain), then press `F1 → Wokwi: Start Simulator`.

If Wokwi reports `firmware binary .pio/build/esp32dev/firmware.bin not found`,
the build has not completed; check `pio run -e esp32dev` output and retry.

## Option 0b: Wokwi CLI (cloud simulation)

The standalone CLI is installed at `~/.wokwi/bin/wokwi-cli` in this
environment (v0.29.0). It is not on the default `PATH`:

```bash
cd esp32
pio run -e esp32dev
export WOKWI_CLI_TOKEN="..."   # from https://wokwi.com/dashboard/ci
~/.wokwi/bin/wokwi-cli . --timeout 60000 --serial-log-file /tmp/wokwi-serial.log
```

Build the firmware first; `wokwi.toml` points at
`.pio/build/esp32dev/firmware.bin`. The CLI runs the simulation in Wokwi's
cloud, so the MQTT broker must still be internet-reachable (Option A or B).
`WOKWI_CLI_TOKEN` is a secret: never commit it or put it in the repository.

To drive the wildlife input automatically, run the checked-in scenario:

```bash
~/.wokwi/bin/wokwi-cli . --scenario scenarios/wildlife.yaml \
  --timeout 60000 --serial-log-file /tmp/wokwi-wildlife.log
```

The scenario waits for `MQTT connected`, presses the `wildlife` button for
2.5 seconds, then releases it. Firmware status changes are printed as
`STATE ...` lines on the serial console. This scenario completed successfully
on 2026-10-21 using the Pinggy tunnel: serial showed `MQTT connected` and
`STATE LOCAL WILDLIFE`; the live Godot monitor saw `external=true`, `STOP`, and
RED, then release with the backend held in `RECOVERY_REQUIRED`.

## Option A: tunnel a local broker (Pinggy, verified)

Wokwi needs a public **raw TCP** endpoint. Cloudflare Quick Tunnels only proxy
HTTP/WebSocket traffic, so `cloudflared tunnel --url tcp://localhost:1883`
cannot carry MQTT. Use the checked-in Pinggy helper instead:

```bash
./scripts/wokwi-tunnel.sh --write-secrets
```

The script starts a temporary raw TCP tunnel to local port 1883, waits for the
public `tcp://host:port` address, and (with `--write-secrets`) writes the
git-ignored `esp32/secrets.h` using the `esp32` broker user. Keep it running
for the duration of the simulation; the free tunnel expires after about an
hour. Then rebuild and start Wokwi:

```bash
cd esp32
pio run -e esp32dev
~/.wokwi/bin/wokwi-cli . --scenario scenarios/wildlife.yaml --timeout 60000
```

Use `MQTT_LOCAL_PORT=1884 ./scripts/wokwi-tunnel.sh` when the host broker is
not on 1883. Never commit `secrets.h`, and never use `localhost` or
`127.0.0.1` in the device configuration.

The older `ngrok tcp 1883` workflow also works if ngrok is installed. A named
Cloudflare tunnel with a client-side TCP route is possible but needs an
account and is not part of this demo.

## Option B: internet-reachable broker

Point `MQTT_HOST`/`MQTT_PORT` at any broker that has the `esp32` user and the
project ACLs from `mosquitto/acl_file`.

## Verify

Watch telemetry from the host:

```bash
mosquitto_sub -h 127.0.0.1 -p 1883 -u backend -P backend-dev-pass \
  -t 'railway/telemetry/esp32' -v
```

Publish a test command (backend credentials are required because the ESP32 is
only allowed to receive commands):

```bash
mosquitto_pub -h 127.0.0.1 -p 1883 -u backend -P backend-dev-pass \
  -t railway/commands/esp32 \
  -m '{"request_id":"manual-1","zone":"zone1","event":"WILDLIFE_DETECTED","timestamp":"2026-10-20T12:00:00.000Z","source":"dashboard","payload":{}}'
```

Expected device behaviour: red LED, barrier down (servo 90°), OLED shows
`WILDLIFE`, and telemetry includes `distanceM`, `motion`, and `vibration`.

## Live animation

With the broker, backend, and Godot twin running, the ESP32 telemetry drives
the same hazard path as the dashboard:

1. Open the Godot demo (`godot/scenes/lts_full.tscn`).
2. Start the Wokwi scenario. The `wildlife` button produces
   `wildlifeDetected: true`; the backend raises the zone hazard and the twin
   spawns a deer, lowers both barriers, and stops the train.
3. Releasing the button publishes `wildlifeDetected: false`. The local animal
   hazard clears, but the backend remains in recovery until the dashboard
   sends `RESET`. This is intentional: the backend is authoritative.
