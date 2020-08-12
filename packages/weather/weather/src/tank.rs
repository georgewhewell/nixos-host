use linux_embedded_hal::I2cdev;
use serde::Serialize;
use serde_json::json;
use shared_bus;
use vl53l0x::VL53L0x;
use i2cdev::linux::LinuxI2CError;

#[derive(Serialize)]
pub struct TankState {
    mm: u16,
}

pub fn config() -> serde_json::value::Value {
    json!({
        "name": "water_tank".to_string(),
        "device_class": "sensor",
        "unit_of_measurement": "%",
        "value_template": "{{value_json['water_level']}}",
        "platform": "farmbot"
    })
}

pub fn read_tank_level() -> Result<u16, LinuxI2CError> {
    println!("Reading tank level!");
    let i2c_bus = I2cdev::new("/dev/i2c-0")?;
    let manager = shared_bus::BusManager::<std::sync::Mutex<_>, _>::new(i2c_bus);

    let mut tof = VL53L0x::new(manager.acquire()).unwrap();

    match tof.read_range_single_millimeters_blocking() {
        Ok(meas) => Ok(meas),
        Err(_e) => Ok(0.0 as u16),
    }
}
