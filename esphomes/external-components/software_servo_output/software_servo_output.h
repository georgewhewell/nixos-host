#pragma once

#include "driver/gptimer.h"
#include "esphome/components/output/float_output.h"
#include "esphome/core/component.h"
#include "esphome/core/hal.h"

namespace esphome::software_servo_output {

class SoftwareServoOutput : public output::FloatOutput, public Component {
 public:
  explicit SoftwareServoOutput(InternalGPIOPin *pin) : pin_(pin) {}

  void setup() override;
  void dump_config() override;
  void on_shutdown() override;
  float get_setup_priority() const override { return setup_priority::HARDWARE; }

 protected:
  static constexpr uint32_t PERIOD_US = 20000;
  static constexpr uint32_t MIN_PULSE_US = 500;
  static constexpr uint32_t MAX_PULSE_US = 2500;

  void write_state(float state) override;
  static bool IRAM_ATTR on_alarm_(gptimer_handle_t timer, const gptimer_alarm_event_data_t *event, void *context);
  void cleanup_timer_();

  InternalGPIOPin *pin_;
  ISRInternalGPIOPin isr_pin_;
  gptimer_handle_t timer_{nullptr};
  volatile uint32_t requested_pulse_us_{0};
  uint32_t active_pulse_us_{0};
  bool pin_high_{false};
};

}  // namespace esphome::software_servo_output
