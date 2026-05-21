#include "lis3dh.h"

#include "esphome/core/log.h"

namespace esphome {
namespace lis3dh {

static const char *const TAG = "lis3dh";

static const uint8_t LIS3DH_REG_TEMP_CFG = 0x1F;
static const uint8_t LIS3DH_REG_CTRL1 = 0x20;
static const uint8_t LIS3DH_REG_CTRL4 = 0x23;
static const uint8_t LIS3DH_REG_OUT_ADC1_L = 0x08;
static const uint8_t LIS3DH_REG_OUT_X_L = 0x28;
static const uint8_t LIS3DH_REG_WHO_AM_I = 0x0F;

static const uint8_t LIS3DH_WHO_AM_I_RESPONSE = 0x33;
static const uint8_t LIS3DH_I2C_AUTO_INCREMENT = 0x80;

static const uint8_t LIS3DH_TEMP_CFG_ADC_EN = 0x80;
static const uint8_t LIS3DH_TEMP_CFG_TEMP_EN = 0x40;

static const uint8_t LIS3DH_CTRL1_ODR_50_HZ = 0x40;
static const uint8_t LIS3DH_CTRL1_AXES_ENABLE = 0x07;

static const uint8_t LIS3DH_CTRL4_BDU = 0x80;
static const uint8_t LIS3DH_CTRL4_HR = 0x08;

static const float GRAVITY_EARTH = 9.80665f;
static const float LIS3DH_HR_2G_MG_PER_DIGIT = 1.0f;

int16_t LIS3DHComponent::parse_le_int16_(uint8_t lsb, uint8_t msb) {
  return static_cast<int16_t>(static_cast<uint16_t>(lsb) | (static_cast<uint16_t>(msb) << 8));
}

int16_t LIS3DHComponent::parse_left_aligned_12bit_(uint8_t lsb, uint8_t msb) {
  return parse_le_int16_(lsb, msb) / 16;
}

int16_t LIS3DHComponent::parse_left_aligned_10bit_(uint8_t lsb, uint8_t msb) {
  return parse_le_int16_(lsb, msb) / 64;
}

bool LIS3DHComponent::has_acceleration_sensors_() const {
  return this->acceleration_x_sensor_ != nullptr || this->acceleration_y_sensor_ != nullptr ||
         this->acceleration_z_sensor_ != nullptr;
}

bool LIS3DHComponent::has_aux_sensors_() const {
  return this->temperature_sensor_ != nullptr || this->adc1_sensor_ != nullptr || this->adc2_sensor_ != nullptr ||
         this->adc3_sensor_ != nullptr;
}

void LIS3DHComponent::setup() {
  uint8_t who_am_i = 0;
  if (!this->read_byte(LIS3DH_REG_WHO_AM_I, &who_am_i) || who_am_i != LIS3DH_WHO_AM_I_RESPONSE) {
    ESP_LOGE(TAG, "Communication with LIS3DH failed, WHO_AM_I=0x%02X", who_am_i);
    this->mark_failed();
    return;
  }

  if (!this->write_byte(LIS3DH_REG_CTRL1, LIS3DH_CTRL1_ODR_50_HZ | LIS3DH_CTRL1_AXES_ENABLE)) {
    this->mark_failed();
    return;
  }

  if (!this->write_byte(LIS3DH_REG_CTRL4, LIS3DH_CTRL4_BDU | LIS3DH_CTRL4_HR)) {
    this->mark_failed();
    return;
  }

  uint8_t temp_cfg = 0x00;
  if (this->has_aux_sensors_()) {
    temp_cfg |= LIS3DH_TEMP_CFG_ADC_EN;
  }
  if (this->temperature_sensor_ != nullptr) {
    temp_cfg |= LIS3DH_TEMP_CFG_TEMP_EN;
  }
  if (!this->write_byte(LIS3DH_REG_TEMP_CFG, temp_cfg)) {
    this->mark_failed();
    return;
  }
}

void LIS3DHComponent::dump_config() {
  ESP_LOGCONFIG(TAG, "LIS3DH:");
  LOG_I2C_DEVICE(this);
  if (this->is_failed()) {
    ESP_LOGE(TAG, ESP_LOG_MSG_COMM_FAIL);
  }
  LOG_UPDATE_INTERVAL(this);
  LOG_SENSOR("  ", "Acceleration X", this->acceleration_x_sensor_);
  LOG_SENSOR("  ", "Acceleration Y", this->acceleration_y_sensor_);
  LOG_SENSOR("  ", "Acceleration Z", this->acceleration_z_sensor_);
  LOG_SENSOR("  ", "Temperature", this->temperature_sensor_);
  if (this->temperature_sensor_ != nullptr) {
    ESP_LOGCONFIG(TAG, "  Temperature sensor is on-die and may need an offset filter");
  }
  LOG_SENSOR("  ", "ADC1", this->adc1_sensor_);
  LOG_SENSOR("  ", "ADC2", this->adc2_sensor_);
  LOG_SENSOR("  ", "ADC3", this->adc3_sensor_);
}

void LIS3DHComponent::update() {
  if (this->has_acceleration_sensors_()) {
    uint8_t accel_data[6];
    if (!this->read_bytes(LIS3DH_REG_OUT_X_L | LIS3DH_I2C_AUTO_INCREMENT, accel_data,
                          sizeof(accel_data))) {
      this->status_set_warning();
      return;
    }

    const float accel_scale = LIS3DH_HR_2G_MG_PER_DIGIT * 0.001f * GRAVITY_EARTH;
    const float x =
        static_cast<float>(parse_left_aligned_12bit_(accel_data[0], accel_data[1])) * accel_scale;
    const float y =
        static_cast<float>(parse_left_aligned_12bit_(accel_data[2], accel_data[3])) * accel_scale;
    const float z =
        static_cast<float>(parse_left_aligned_12bit_(accel_data[4], accel_data[5])) * accel_scale;

    ESP_LOGV(TAG, "Acceleration x=%.3f y=%.3f z=%.3f m/s^2", x, y, z);

    if (this->acceleration_x_sensor_ != nullptr)
      this->acceleration_x_sensor_->publish_state(x);
    if (this->acceleration_y_sensor_ != nullptr)
      this->acceleration_y_sensor_->publish_state(y);
    if (this->acceleration_z_sensor_ != nullptr)
      this->acceleration_z_sensor_->publish_state(z);
  }

  if (this->has_aux_sensors_()) {
    uint8_t aux_data[6];
    if (!this->read_bytes(LIS3DH_REG_OUT_ADC1_L | LIS3DH_I2C_AUTO_INCREMENT, aux_data,
                          sizeof(aux_data))) {
      this->status_set_warning();
      return;
    }

    if (this->adc1_sensor_ != nullptr) {
      const int16_t adc1 = parse_left_aligned_10bit_(aux_data[0], aux_data[1]);
      this->adc1_sensor_->publish_state(adc1);
    }
    if (this->adc2_sensor_ != nullptr) {
      const int16_t adc2 = parse_left_aligned_10bit_(aux_data[2], aux_data[3]);
      this->adc2_sensor_->publish_state(adc2);
    }
    if (this->adc3_sensor_ != nullptr) {
      const int16_t adc3 = parse_left_aligned_10bit_(aux_data[4], aux_data[5]);
      this->adc3_sensor_->publish_state(adc3);
    }
    if (this->temperature_sensor_ != nullptr) {
      const int8_t raw_temp = static_cast<int8_t>(aux_data[5]);
      const float temperature_c = 25.0f + static_cast<float>(raw_temp);
      this->temperature_sensor_->publish_state(temperature_c);
    }
  }

  this->status_clear_warning();
}

}  // namespace lis3dh
}  // namespace esphome
