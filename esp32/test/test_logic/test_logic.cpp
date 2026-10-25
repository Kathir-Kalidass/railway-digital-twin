#include <unity.h>

#include <cstring>

#include "debounce.h"
#include "output_logic.h"
#include "command_logic.h"
#include "telemetry.h"
#include "sensors.h"
#include "actuator.h"
#include "epoch.h"

void test_epoch_source_not_calibrated_before_update() {
  EpochSource source;
  TEST_ASSERT_FALSE(source.calibrated);
  TEST_ASSERT_EQUAL(0, source.nowMs(12345));
}

void test_epoch_source_rejects_bogus_epoch() {
  EpochSource source;
  source.update(1000, 500);  // epoch near the Unix start; not a real wall clock
  TEST_ASSERT_FALSE(source.calibrated);
  TEST_ASSERT_FALSE(source.validNow(1000));
}

void test_epoch_source_derives_wall_clock() {
  EpochSource source;
  source.update(1700000000000ULL, 1000);
  TEST_ASSERT_TRUE(source.calibrated);
  TEST_ASSERT_EQUAL(1700000004000, source.nowMs(5000));
  TEST_ASSERT_TRUE(source.validNow(5000));
}

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

void test_backend_near_warning_is_local() {
  TEST_ASSERT_EQUAL(static_cast<int>(Output::WARNING),
                    static_cast<int>(decide_output(false, false, true, false, true)));
  TEST_ASSERT_EQUAL(static_cast<int>(Output::RENDER_BACKEND),
                    static_cast<int>(decide_output(false, false, true, true, true)));
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

void test_command_accepts_backend_source_for_wildlife() {
  const std::string detected =
      "{\"event\":\"WILDLIFE_DETECTED\",\"zone\":\"zone1\",\"source\":\"backend\",\"timestamp\":\"2026-10-22T00:00:00.000Z\"}";
  TEST_ASSERT_EQUAL(static_cast<int>(CmdEffect::WILDLIFE_SET),
                    static_cast<int>(parse_command(detected, "zone1", 0)));

  const std::string cleared =
      "{\"event\":\"WILDLIFE_CLEARED\",\"zone\":\"zone1\",\"source\":\"backend\",\"timestamp\":\"2026-10-22T00:00:00.000Z\"}";
  TEST_ASSERT_EQUAL(static_cast<int>(CmdEffect::WILDLIFE_CLEAR),
                    static_cast<int>(parse_command(cleared, "zone1", 0)));

  const std::string fault_from_backend =
      "{\"event\":\"SENSOR_FAULT\",\"zone\":\"zone1\",\"source\":\"backend\",\"timestamp\":\"2026-10-22T00:00:00.000Z\"}";
  TEST_ASSERT_EQUAL(static_cast<int>(CmdEffect::NONE),
                    static_cast<int>(parse_command(fault_from_backend, "zone1", 0)));

  const std::string near =
      "{\"event\":\"WILDLIFE_NEAR\",\"zone\":\"zone1\",\"source\":\"backend\",\"timestamp\":\"2026-10-22T00:00:00.000Z\"}";
  TEST_ASSERT_EQUAL(static_cast<int>(CmdEffect::WILDLIFE_NEAR),
                    static_cast<int>(parse_command(near, "zone1", 0)));

  const std::string near_clear =
      "{\"event\":\"WILDLIFE_NEAR_CLEAR\",\"zone\":\"zone1\",\"source\":\"backend\",\"timestamp\":\"2026-10-22T00:00:00.000Z\"}";
  TEST_ASSERT_EQUAL(static_cast<int>(CmdEffect::WILDLIFE_NEAR_CLEAR),
                    static_cast<int>(parse_command(near_clear, "zone1", 0)));

  const std::string reset_from_backend =
      "{\"event\":\"RESET\",\"zone\":\"zone1\",\"source\":\"backend\",\"timestamp\":\"2026-10-22T00:00:00.000Z\"}";
  TEST_ASSERT_EQUAL(static_cast<int>(CmdEffect::NONE),
                    static_cast<int>(parse_command(reset_from_backend, "zone1", 0)));

  const std::string dashboard_ok =
      "{\"event\":\"RESET\",\"zone\":\"zone1\",\"source\":\"dashboard\",\"timestamp\":\"2026-10-22T00:00:00.000Z\"}";
  TEST_ASSERT_EQUAL(static_cast<int>(CmdEffect::RESET),
                    static_cast<int>(parse_command(dashboard_ok, "zone1", 0)));
}

void test_animal_detected_any_channel() {
  TEST_ASSERT_TRUE(animal_detected(true, 400, 0, 100, 500));
  TEST_ASSERT_TRUE(animal_detected(false, 60, 0, 100, 500));
  TEST_ASSERT_TRUE(animal_detected(false, 400, 800, 100, 500));
  TEST_ASSERT_FALSE(animal_detected(false, 400, 100, 100, 500));
  TEST_ASSERT_FALSE(animal_detected(false, -1, 0, 100, 500));
}

void test_distance_conversion() {
  TEST_ASSERT_EQUAL_FLOAT(0.42f, distance_cm_to_m(42));
  TEST_ASSERT_EQUAL_FLOAT(-1.0f, distance_cm_to_m(-1));
}

void test_barrier_and_status() {
  TEST_ASSERT_EQUAL_INT(90, barrier_angle(true));
  TEST_ASSERT_EQUAL_INT(0, barrier_angle(false));
  TEST_ASSERT_EQUAL_STRING("LOCAL WILDLIFE", status_line(true, false, true, false));
  TEST_ASSERT_EQUAL_STRING("SENSOR FAULT", status_line(false, true, true, false));
  TEST_ASSERT_EQUAL_STRING("COMM LOSS", status_line(false, false, false, false));
  TEST_ASSERT_EQUAL_STRING("WILDLIFE", status_line(false, false, true, true));
  TEST_ASSERT_EQUAL_STRING("ANIMAL NEAR", status_line(false, false, true, false, true));
  TEST_ASSERT_EQUAL_STRING("CLEAR", status_line(false, false, true, false));
}

void test_request_id_unique_across_boots() {
  // Sequence resets on reboot; the boot nonce must keep ids unique.
  const std::string first = build_request_id("esp32", 0x1122334455667788ULL, 1000, 1);
  const std::string rebooted = build_request_id("esp32", 0x1122334455667788ULL, 48291, 1);
  const std::string later = build_request_id("esp32", 0x1122334455667788ULL, 1000, 2);
  TEST_ASSERT_TRUE(first.find("esp32-1122334455667788-1000-1") == 0);
  TEST_ASSERT_EQUAL(1, first == rebooted ? 0 : 1);
  TEST_ASSERT_EQUAL(1, first == later ? 0 : 1);
}

void test_telemetry_extended_fields() {
  const std::string json =
      build_telemetry("esp32", "zone1", "req-1", "2026-10-19T12:00:00.000Z", true,
                      true, true, 7000, 0.42f, true, 700, true);
  TEST_ASSERT_NOT_NULL(strstr(json.c_str(), "\"distanceM\":0.42"));
  TEST_ASSERT_NOT_NULL(strstr(json.c_str(), "\"motion\":true"));
  TEST_ASSERT_NOT_NULL(strstr(json.c_str(), "\"vibration\":700"));
  TEST_ASSERT_NOT_NULL(strstr(json.c_str(), "\"nearAnimal\":true"));
}

int main(int, char **) {
  UNITY_BEGIN();
  RUN_TEST(test_local_wildlife_dominates);
  RUN_TEST(test_local_fault_dominates_command);
  RUN_TEST(test_comm_loss_restrictive);
  RUN_TEST(test_backend_state_is_rendered_when_safe);
  RUN_TEST(test_backend_near_warning_is_local);
  RUN_TEST(test_debounce_ignores_bounce);
  RUN_TEST(test_telemetry_envelope);
  RUN_TEST(test_telemetry_clock_invalid);
  RUN_TEST(test_command_rejects_other_zone);
  RUN_TEST(test_command_accepts_same_zone);
  RUN_TEST(test_command_rejects_malformed);
  RUN_TEST(test_command_accepts_backend_source_for_wildlife);
  RUN_TEST(test_animal_detected_any_channel);
  RUN_TEST(test_distance_conversion);
  RUN_TEST(test_barrier_and_status);
  RUN_TEST(test_telemetry_extended_fields);
  RUN_TEST(test_epoch_source_not_calibrated_before_update);
  RUN_TEST(test_epoch_source_rejects_bogus_epoch);
  RUN_TEST(test_epoch_source_derives_wall_clock);
  RUN_TEST(test_request_id_unique_across_boots);
  return UNITY_END();
}
