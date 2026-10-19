#include <unity.h>

#include <cstring>

#include "debounce.h"
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

int main(int, char **) {
  UNITY_BEGIN();
  RUN_TEST(test_local_wildlife_dominates);
  RUN_TEST(test_local_fault_dominates_command);
  RUN_TEST(test_comm_loss_restrictive);
  RUN_TEST(test_backend_state_is_rendered_when_safe);
  RUN_TEST(test_debounce_ignores_bounce);
  RUN_TEST(test_telemetry_envelope);
  RUN_TEST(test_telemetry_clock_invalid);
  return UNITY_END();
}
