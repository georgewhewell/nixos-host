use anyhow::Result;
use bme280::BME280;
use linux_embedded_hal::{Delay, I2cdev};
use log::info;
use serde_json::json;
use titlecase::titlecase;

use std::time;

use crate::mqtt::{MQTTDevice, MQTTSensorConfig};

#[derive(Debug)]
pub struct WeatherSensor {
    last_read: time::Instant,
    temperature: f32,
    pressure: f32,
    humidity: f32,
}

fn read() -> Result<(f32, f32, f32)> {
    let i2c_bus = I2cdev::new("/dev/i2c-0")?;
    let mut bme280 = BME280::new_primary(i2c_bus, Delay);

    bme280.init().unwrap();
    std::thread::sleep(time::Duration::from_millis(100));

    let m = bme280.measure().unwrap();
    Ok((m.temperature, m.pressure, m.humidity))
}

impl WeatherSensor {
    pub fn should_read(&self) -> bool {
        self.last_read + time::Duration::from_millis(30000) < time::Instant::now()
    }

    pub fn new() -> Result<Self> {
        info!("Creating weather sensor");
        let (t, p, h) = read()?;
        Ok(WeatherSensor {
            last_read: time::Instant::now(),
            temperature: t,
            pressure: p,
            humidity: h,
        })
    }

    pub fn mqtt_state(&mut self) -> Result<serde_json::Value> {
        info!("Reading weather sensor");
        let (t, p, h) = read()?;
        self.last_read = time::Instant::now();
        Ok(json!({
            "temperature": t,
            "pressure": p,
            "humidity": h,
        }))
    }

    fn build_mqtt_config(
        &self,
        suffix: String,
        unit_of_measurement: String,
        device_class: Option<String>,
    ) -> MQTTSensorConfig {
        MQTTSensorConfig {
            name: format!("{}", titlecase(&suffix)),
            unique_id: format!("farmbot-{}", suffix),
            unit_of_measurement: unit_of_measurement,
            device_class: device_class,
            state_topic: "homeassistant/sensor/farmbot/weather/state".to_string(),
            value_template: format!("{{{{ value_json.{} }}}}", suffix),
            device: MQTTDevice {
                identifiers: vec!["farmbot".to_string()],
                connections: vec![],
                manufacturer: "Whewell Comms".to_string(),
                name: "Farmbot".to_string(),
                model: "Farmbot 0.1".to_string(),
            },
        }
    }

    pub fn mqtt_config(&self) -> Vec<MQTTSensorConfig> {
        vec![
            self.build_mqtt_config(
                "temperature".to_string(),
                "°C".to_string(),
                Some("temperature".to_string()),
            ),
            self.build_mqtt_config(
                "humidity".to_string(),
                "%".to_string(),
                Some("humidity".to_string()),
            ),
            self.build_mqtt_config(
                "pressure".to_string(),
                "mbar".to_string(),
                Some("pressure".to_string()),
            ),
        ]
    }
}
