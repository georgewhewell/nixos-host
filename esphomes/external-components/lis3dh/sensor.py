import esphome.codegen as cg
from esphome.components import i2c, sensor
import esphome.config_validation as cv
from esphome.const import (
    CONF_ACCELERATION_X,
    CONF_ACCELERATION_Y,
    CONF_ACCELERATION_Z,
    CONF_ID,
    CONF_TEMPERATURE,
    DEVICE_CLASS_TEMPERATURE,
    ICON_ACCELERATION_X,
    ICON_ACCELERATION_Y,
    ICON_ACCELERATION_Z,
    ICON_GAUGE,
    STATE_CLASS_MEASUREMENT,
    UNIT_CELSIUS,
    UNIT_EMPTY,
    UNIT_METER_PER_SECOND_SQUARED,
)

DEPENDENCIES = ["i2c"]

CONF_ADC1 = "adc1"
CONF_ADC2 = "adc2"
CONF_ADC3 = "adc3"

ACCELERATION_SENSORS = (
    CONF_ACCELERATION_X,
    CONF_ACCELERATION_Y,
    CONF_ACCELERATION_Z,
)
AUX_SENSORS = (CONF_ADC1, CONF_ADC2, CONF_ADC3, CONF_TEMPERATURE)

lis3dh_ns = cg.esphome_ns.namespace("lis3dh")
LIS3DHComponent = lis3dh_ns.class_(
    "LIS3DHComponent", cg.PollingComponent, i2c.I2CDevice
)

accel_schema = {
    "unit_of_measurement": UNIT_METER_PER_SECOND_SQUARED,
    "accuracy_decimals": 2,
    "state_class": STATE_CLASS_MEASUREMENT,
}
adc_schema = sensor.sensor_schema(
    unit_of_measurement=UNIT_EMPTY,
    icon=ICON_GAUGE,
    accuracy_decimals=0,
    state_class=STATE_CLASS_MEASUREMENT,
)
temperature_schema = sensor.sensor_schema(
    unit_of_measurement=UNIT_CELSIUS,
    accuracy_decimals=1,
    device_class=DEVICE_CLASS_TEMPERATURE,
    state_class=STATE_CLASS_MEASUREMENT,
)

CONFIG_SCHEMA = cv.All(
    cv.Schema(
        {
            cv.GenerateID(): cv.declare_id(LIS3DHComponent),
            cv.Optional(CONF_ACCELERATION_X): sensor.sensor_schema(
                icon=ICON_ACCELERATION_X,
                **accel_schema,
            ),
            cv.Optional(CONF_ACCELERATION_Y): sensor.sensor_schema(
                icon=ICON_ACCELERATION_Y,
                **accel_schema,
            ),
            cv.Optional(CONF_ACCELERATION_Z): sensor.sensor_schema(
                icon=ICON_ACCELERATION_Z,
                **accel_schema,
            ),
            cv.Optional(CONF_TEMPERATURE): temperature_schema,
            cv.Optional(CONF_ADC1): adc_schema,
            cv.Optional(CONF_ADC2): adc_schema,
            cv.Optional(CONF_ADC3): adc_schema,
        }
    )
    .extend(cv.polling_component_schema("60s"))
    .extend(i2c.i2c_device_schema(0x18)),
    cv.has_at_most_one_key(CONF_TEMPERATURE, CONF_ADC3),
    cv.has_at_least_one_key(*ACCELERATION_SENSORS, *AUX_SENSORS),
)


async def to_code(config):
    var = cg.new_Pvariable(config[CONF_ID])
    await cg.register_component(var, config)
    await i2c.register_i2c_device(var, config)

    for sensor_key in ACCELERATION_SENSORS:
        if sensor_key in config:
            sens = await sensor.new_sensor(config[sensor_key])
            cg.add(getattr(var, f"set_{sensor_key}_sensor")(sens))

    for sensor_key in (CONF_ADC1, CONF_ADC2, CONF_ADC3):
        if sensor_key in config:
            sens = await sensor.new_sensor(config[sensor_key])
            cg.add(getattr(var, f"set_{sensor_key}_sensor")(sens))

    if CONF_TEMPERATURE in config:
        sens = await sensor.new_sensor(config[CONF_TEMPERATURE])
        cg.add(var.set_temperature_sensor(sens))
