# Railway Digital Twin operations guide

This document captures the local developer workflow and the operational safety boundaries for the Railway Digital Twin.

## Supported local developer path

1. Install Docker Engine/Compose and the Node.js toolchain.
2. Copy `.env.sample` to `.env` and set unique local secrets.
3. Run `./scripts/dev-up.sh`.
4. Confirm backend health via `curl -s http://localhost:3001/api/health`.
5. Open the dashboard at `http://localhost:5173`.
6. Use the `viewer`, `operator`, and `admin` seed accounts defined in `.env`.

## Local identity and broker credentials

The local stack uses per-client Mosquitto authentication. The supported identities are:

- `godot`
- `esp32`
- `backend`
- `dashboard`

Passwords are generated from local variables in `.env` and then converted into the broker password file by `scripts/mosquitto_setup.sh`. Never commit the generated `mosquitto/password_file` or your local `.env` file.

## Health and readiness

The backend health endpoint is:

```bash
curl -s http://localhost:3001/api/health
```

Expected response:

```json
{"ok":true,"mqttConnected":true}
```

`dev-up.sh` waits up to 60 seconds for this condition before it exits with an error.

## Safe recovery

- If the MQTT broker is down, regenerate credentials: `./scripts/mosquitto_setup.sh`.
- If a service is unhealthy, inspect: `docker compose ps` and `docker compose logs backend mqtt web`.
- If the dashboard cannot authenticate, confirm the backend is running and the `.env` file contains the expected passwords.
- Reset only the local SQLite database in the named Docker volume if you intentionally want to clear state. Do not remove unrelated Docker volumes or user data.

## Demo and verification

- `./scripts/demo-scenarios.sh` exercises the authenticated control flow and validates the response payloads using `jq`.
- `./scripts/verify-all.sh` runs the backend suite, web build, ACL checks, and optional hardware/Godot compile gates.
- `npm --prefix backend test` remains the primary backend regression guard.

## Safety boundary

This project is an educational simulation for local testing only. It is not a production railway signalling system, and it must never be connected to live infrastructure or real trains.
