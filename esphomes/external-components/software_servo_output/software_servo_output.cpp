#include "software_servo_output.h"

#include "esp_err.h"
#include "esphome/core/log.h"

namespace esphome::software_servo_output {

static const char *const TAG = "software_servo_output";

void SoftwareServoOutput::setup() {
  this->pin_->setup();
  this->pin_->digital_write(false);
  this->isr_pin_ = this->pin_->to_isr();

  gptimer_config_t timer_config{};
  timer_config.clk_src = GPTIMER_CLK_SRC_DEFAULT;
  timer_config.direction = GPTIMER_COUNT_UP;
  timer_config.resolution_hz = 1000000;

  esp_err_t error = gptimer_new_timer(&timer_config, &this->timer_);
  if (error != ESP_OK) {
    ESP_LOGE(TAG, "Unable to allocate timer: %s", esp_err_to_name(error));
    this->mark_failed();
    return;
  }

  gptimer_event_callbacks_t callbacks{};
  callbacks.on_alarm = &SoftwareServoOutput::on_alarm_;
  error = gptimer_register_event_callbacks(this->timer_, &callbacks, this);
  if (error != ESP_OK) {
    ESP_LOGE(TAG, "Unable to register timer callback: %s", esp_err_to_name(error));
    this->cleanup_timer_();
    this->mark_failed();
    return;
  }

  gptimer_alarm_config_t alarm{};
  alarm.alarm_count = PERIOD_US;
  alarm.flags.auto_reload_on_alarm = false;
  error = gptimer_set_alarm_action(this->timer_, &alarm);
  if (error == ESP_OK)
    error = gptimer_enable(this->timer_);
  if (error == ESP_OK)
    error = gptimer_start(this->timer_);
  if (error != ESP_OK) {
    ESP_LOGE(TAG, "Unable to start timer: %s", esp_err_to_name(error));
    this->cleanup_timer_();
    this->mark_failed();
  }
}

void SoftwareServoOutput::dump_config() {
  ESP_LOGCONFIG(TAG, "Software Servo Output:");
  LOG_PIN("  Pin: ", this->pin_);
  ESP_LOGCONFIG(TAG,
                "  Frequency: 50 Hz\n"
                "  Pulse range: %u-%u us",
                MIN_PULSE_US, MAX_PULSE_US);
  if (this->is_failed())
    ESP_LOGE(TAG, "  Setup failed");
  LOG_FLOAT_OUTPUT(this);
}

void SoftwareServoOutput::write_state(float state) {
  if (state <= 0.0f) {
    this->requested_pulse_us_ = 0;
    this->pin_->digital_write(false);
    return;
  }

  uint32_t pulse_us = static_cast<uint32_t>(state * static_cast<float>(PERIOD_US) + 0.5f);
  if (pulse_us < MIN_PULSE_US)
    pulse_us = MIN_PULSE_US;
  if (pulse_us > MAX_PULSE_US)
    pulse_us = MAX_PULSE_US;
  this->requested_pulse_us_ = pulse_us;
}

bool IRAM_ATTR SoftwareServoOutput::on_alarm_(gptimer_handle_t timer,
                                              const gptimer_alarm_event_data_t *event, void *context) {
  auto *output = static_cast<SoftwareServoOutput *>(context);
  uint32_t next_delay_us;

  if (output->pin_high_) {
    output->isr_pin_.digital_write(false);
    output->pin_high_ = false;
    next_delay_us = PERIOD_US - output->active_pulse_us_;
  } else {
    const uint32_t pulse_us = output->requested_pulse_us_;
    if (pulse_us == 0) {
      output->isr_pin_.digital_write(false);
      next_delay_us = PERIOD_US;
    } else {
      output->active_pulse_us_ = pulse_us;
      output->isr_pin_.digital_write(true);
      output->pin_high_ = true;
      next_delay_us = pulse_us;
    }
  }

  gptimer_alarm_config_t alarm{};
  alarm.alarm_count = event->count_value + next_delay_us;
  alarm.flags.auto_reload_on_alarm = false;
  gptimer_set_alarm_action(timer, &alarm);
  return false;
}

void SoftwareServoOutput::cleanup_timer_() {
  if (this->timer_ == nullptr)
    return;
  gptimer_stop(this->timer_);
  gptimer_disable(this->timer_);
  gptimer_del_timer(this->timer_);
  this->timer_ = nullptr;
}

void SoftwareServoOutput::on_shutdown() {
  this->requested_pulse_us_ = 0;
  this->pin_->digital_write(false);
  this->cleanup_timer_();
}

}  // namespace esphome::software_servo_output
