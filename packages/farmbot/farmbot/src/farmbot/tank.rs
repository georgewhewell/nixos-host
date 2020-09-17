use anyhow::Result;
use linux_embedded_hal::I2cdev;
use log::info;
use serde_json::json;
use std::time::{Duration, Instant};
use vl53l0x::VL53L0x;

use crate::mqtt::{MQTTDevice, MQTTSensorConfig};

#[derive(Debug)]
pub struct TankLevelSensor {
    level: u16,
    last_read: Instant,
}

fn read() -> Result<u16> {
    let i2c_bus = I2cdev::new("/dev/i2c-0")?;
    let mut tof = VL53L0x::new(i2c_bus).expect("Error initialising VL53L0x");
    let level = tof
        .read_range_single_millimeters_blocking()
        .expect("Error reading tank level");
    info!("Read level: {}", level);
    Ok(level)
}

impl TankLevelSensor {
    pub fn new() -> Result<Self> {
        info!("Creating tank level sensor");
        return Ok(TankLevelSensor {
            level: read()?,
            last_read: Instant::now(),
        });
    }

    pub fn should_read(&self) -> bool {
        self.last_read + Duration::from_millis(30000) < Instant::now()
    }

    pub fn get(&self) -> u16 {
        self.level
    }

    pub fn mqtt_config(&self) -> MQTTSensorConfig {
        MQTTSensorConfig {
            name: "Water Tank Level".to_string(),
            unique_id: "farmbot-tanklevel".to_string(),
            unit_of_measurement: "mm".to_string(),
            device_class: None,
            state_topic: "homeassistant/sensor/farmbot/tank_level/state".to_string(),
            value_template: "{{ value_json['tank_level'] }}".to_string(),
            device: MQTTDevice {
                identifiers: vec!["farmbot".to_string()],
                connections: vec![],
                manufacturer: "Whewell Comms".to_string(),
                name: "Farmbot".to_string(),
                model: "Farmbot 0.1".to_string(),
            },
        }
    }

    pub fn mqtt_state(tank_level: u16) -> serde_json::Value {
        json!({ "tank_level": tank_level })
    }

    pub fn read(&mut self) -> Result<u16> {
        info!("Attempt to read from VL53L0x");
        let level = read()?;
        self.last_read = Instant::now();
        self.level = level;
        Ok(level)
    }
}
