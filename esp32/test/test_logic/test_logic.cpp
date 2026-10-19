#include <unity.h>

#include <cstring>

#include "debounce.h"
#include "command_logic.h"
#include "output_logic.h"
#include "telemetry.h"

void test_local_wildlife_dominates() {
  TEST_ASSERT_EQUAL(static_cast<int>(Output::RESTRICTIVE),
                    static_cast<int>(decide_output(true, false, true, false)));
}

void test_local_fault_dominates_command() {
  TEST_ASSERT_EQUAL(static_cast<int>(Output::RESTRICTIVE),
                    static_cast<int>(decide_output(false, true, true, false)));
}

void test_comm_loss_restrictive() {
  TEST_ASSERT_EQUAL(static_cast<int>(Output::COMM_LOSS),
                    static_cast<int>(decide_output(false, false, false, false)));
}

void test_backend_state_is_rendered_when_safe() {
  TEST_ASSERT_EQUAL(static_cast<int>(Output::RENDER_BACKEND),
                    static_cast<int>(decide_output(false, false, true, true)));
}

void test_debounce_ignores_bounce() {
  Debouncer d;
  TEST_ASSERT_FALSE(d.update(false, 0));
  TEST_ASSERT_FALSE(d.update(true, 10));
  TEST_ASSERT_TRUE(d.update(true, 100));
}

void test_telemetry_envelope() {
  const std::string json = build_telemetry("esp32", "zone1", "esp32-boot-1-1",
                                           "2026-10-19T12:00:00.000Z", true,
                                           true, false, 12345);
  TEST_ASSERT_NOT_NULL(strstr(json.c_str(), "\"zone\":\"zone1\""));
  TEST_ASSERT_NOT_NULL(strstr(json.c_str(), "\"event\":\"DEVICE_TELEMETRY\""));
  TEST_ASSERT_NOT_NULL(strstr(json.c_str(), "\"clockValid\":true"));
}

void test_telemetry_clock_invalid() {
  const std::string json = build_telemetry("esp32", "zone1", "esp32-boot-1-1", "",
                                           false, false, true, 50);
  TEST_ASSERT_NOT_NULL(strstr(json.c_str(), "\"timestamp\":null"));
  TEST_ASSERT_NOT_NULL(strstr(json.c_str(), "\"clockValid\":false"));
}

void test_command_rejects_other_zone() {
  const std::string json = "{\"event\":\"WILDLIFE_DETECTED\",\"zone\":\"zone2\",\"timestamp\":\"2026-10-19T12:00:00.000Z\"}";
  TEST_ASSERT_EQUAL(static_cast<int>(CmdEffect::NONE),
                    static_cast<int>(parse_command(json, "zone1", 0)));
}

void test_command_accepts_same_zone() {
  const std::string json = "{\"event\":\"SENSOR_FAULT\",\"zone\":\"zone1\",\"timestamp\":\"2026-10-19T12:00:00.000Z\"}";
  TEST_ASSERT_EQUAL(static_cast<int>(CmdEffect::FAULT_SET),
                    static_cast<int>(parse_command(json, "zone1", 0)));
}

void test_command_rejects_malformed() {
  TEST_ASSERT_EQUAL(static_cast<int>(CmdEffect::NONE),
                    static_cast<int>(parse_command("{not json", "zone1", 0)));
}

int main(int, char **) {
  UNITY_BEGIN();
  RUN_TEST(test_local_wildlife_dominates);
  RUN_TEST(test_local_fault_dominates_command);
  RUN_TEST(test_comm_loss_restrictive);
  RUN_TEST(test_backend_state_is_rendered_when_safe);
  RUN_TEST(test_debounce_ignores_bounce);
  RUN_TEST(test_telemetry_envelope);
  RUN_TEST(test_telemetry_clock_invalid);
  RUN_TEST(test_command_rejects_other_zone);
  RUN_TEST(test_command_accepts_same_zone);
  RUN_TEST(test_command_rejects_malformed);
  return UNITY_END();
}
