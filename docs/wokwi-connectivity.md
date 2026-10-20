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

`esp32/wokwi.toml` already points at the PlatformIO build output
(`.pio/build/esp32dev/firmware.bin`). Build with `pio run -e esp32dev`, then
press `F1 → Wokwi: Start Simulator`.

## Option A: tunnel a local broker

1. Start Mosquitto locally:
   ```bash
   docker compose up -d mqtt
   ```
2. Tunnel TCP 1883 with cloudflared:
   ```bash
   cloudflared tunnel --url tcp://localhost:1883
   ```
   or with ngrok:
   ```bash
   ngrok tcp 1883
   ```
3. Copy the public hostname (without `tcp://`) into the Wokwi `secrets.h`:
   ```c
   #define MQTT_HOST "your-tunnel-host.example.com"
   #define MQTT_PORT 18830   // use the port printed by the tunnel
   #define MQTT_USER "esp32"
   #define MQTT_PASS "esp32-dev-pass"
   ```
   Never use `localhost` or `127.0.0.1` in the device configuration.

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
