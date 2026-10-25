import { test } from 'node:test';
import assert from 'node:assert/strict';

test('ESP32 timeout env garbage falls back to defaults', async () => {
  const previous = {
    timeout: process.env.ESP32_TELEMETRY_TIMEOUT_SEC,
    ack: process.env.COMMAND_ACK_TIMEOUT_SEC,
  };
  process.env.ESP32_TELEMETRY_TIMEOUT_SEC = 'banana';
  process.env.COMMAND_ACK_TIMEOUT_SEC = 'not-a-number';
  try {
    const unique = `?test-case=${Date.now()}-${Math.random()}`;
    const { config } = await import(`../src/config.js${unique}`);
    assert.equal(config.esp32TelemetryTimeoutSec, 15);
    assert.equal(config.commandAckTimeoutSec, 10);
  } finally {
    if (previous.timeout === undefined) delete process.env.ESP32_TELEMETRY_TIMEOUT_SEC;
    else process.env.ESP32_TELEMETRY_TIMEOUT_SEC = previous.timeout;
    if (previous.ack === undefined) delete process.env.COMMAND_ACK_TIMEOUT_SEC;
    else process.env.COMMAND_ACK_TIMEOUT_SEC = previous.ack;
  }
});
