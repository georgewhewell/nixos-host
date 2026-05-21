#pragma once

#include "esphome/components/i2c/i2c.h"
#include "esphome/components/sensor/sensor.h"
#include "esphome/core/component.h"

namespace esphome {
namespace lis3dh {

class LIS3DHComponent : public PollingComponent, public i2c::I2CDevice {
 public:
  void setup() override;
  void dump_config() override;
  void update() override;

  void set_acceleration_x_sensor(sensor::Sensor *sensor) {
    this->acceleration_x_sensor_ = sensor;
  }
  void set_acceleration_y_sensor(sensor::Sensor *sensor) {
    this->acceleration_y_sensor_ = sensor;
  }
  void set_acceleration_z_sensor(sensor::Sensor *sensor) {
    this->acceleration_z_sensor_ = sensor;
  }
  void set_temperature_sensor(sensor::Sensor *sensor) {
    this->temperature_sensor_ = sensor;
  }
  void set_adc1_sensor(sensor::Sensor *sensor) { this->adc1_sensor_ = sensor; }
  void set_adc2_sensor(sensor::Sensor *sensor) { this->adc2_sensor_ = sensor; }
  void set_adc3_sensor(sensor::Sensor *sensor) { this->adc3_sensor_ = sensor; }

 protected:
  static int16_t parse_le_int16_(uint8_t lsb, uint8_t msb);
  static int16_t parse_left_aligned_12bit_(uint8_t lsb, uint8_t msb);
  static int16_t parse_left_aligned_10bit_(uint8_t lsb, uint8_t msb);

  bool has_acceleration_sensors_() const;
  bool has_aux_sensors_() const;

  sensor::Sensor *acceleration_x_sensor_{nullptr};
  sensor::Sensor *acceleration_y_sensor_{nullptr};
  sensor::Sensor *acceleration_z_sensor_{nullptr};
  sensor::Sensor *temperature_sensor_{nullptr};
  sensor::Sensor *adc1_sensor_{nullptr};
  sensor::Sensor *adc2_sensor_{nullptr};
  sensor::Sensor *adc3_sensor_{nullptr};
};

}  // namespace lis3dh
}  // namespace esphome
