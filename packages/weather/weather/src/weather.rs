use bme280::{BME280};
use linux_embedded_hal::{Delay, I2cdev};
use i2cdev::linux::LinuxI2CError;
use serde::Serialize;
use serde_json::{json};
use shared_bus;
use std::{time::Duration};
use tokio::time;


use crate::Sensor;

struct FarmbotWeather {
    last_reading: WeatherState,
}


#[derive(Debug, Serialize)]
pub struct WeatherState {
    pub humidity: f32,
    pub temperature: f32,
    pub pressure: f32,
}

pub struct TemperatureSensor {
    pub state: WeatherState,
}
pub struct HumiditySensor {
    pub state: WeatherState,
}
pub struct PressureSensor {
    pub state: WeatherState,
}

impl Sensor for TemperatureSensor {
    fn config(prefix: &str) -> serde_json::value::Value {
        json!([{
            "name": "Outside Temperature",
            "unique_id": "farmbot-temp",
            "unit_of_measurement": "\u{00b0}C",
            "device_class": "temperature",
            "state_topic": format!("{}/state", prefix),
            "value_template":"{{value_json['temperature']}}"
        }])
    }

    fn reading(&self) -> serde_json::value::Value {
        json!({"temperature": self.state.temperature})
    }
}

impl Sensor for HumiditySensor {
    fn config(prefix: &str) -> serde_json::value::Value {
        json!([{
            "name": "Outside Humidity",
            "unique_id": "farmbot-humidity",
            "unit_of_measurement": "\u{00b0}C",
            "device_class": "humidity",
            "state_topic": format!("{}/state", prefix),
            "value_template":"{{value_json['humidity']}}"
        }])
    }

    fn reading(&self) -> serde_json::value::Value {
        json!({"humidity": self.state.humidity})
    }
}

impl Sensor for PressureSensor {
    fn config(prefix: &str) -> serde_json::value::Value {
        json!([{
            "name": "Atmospheric Pressure",
            "unique_id": "farmbot-pressure",
            "unit_of_measurement": "\u{00b0}C",
            "device_class": "pressure",
            "state_topic": format!("{}/state", prefix),
            "value_template":"{{value_json['pressure']}}"
        }])
    }

    fn reading(&self) -> serde_json::value::Value {
        json!({"pressure": self.state.pressure})
    }
}



pub fn config() -> serde_json::value::Value {
    json!([{
        "command_path": "sensor/weather/{}/cmd".to_string(),
        "state_path": "sensor/weather/{}/state",
        "platform": "farmbot",
        "unique_id": "farmbot-weather",
    }])
}

pub async fn read_weather() -> Result<WeatherState, LinuxI2CError> {
    println!("Reading weather!");
    let i2c_bus = I2cdev::new("/dev/i2c-0")?;
    let manager = shared_bus::BusManager::<std::sync::Mutex<_>, _>::new(i2c_bus);
    let mut bme280 = BME280::new_primary(manager.acquire(), Delay);

    bme280.init().unwrap();
    time::delay_for(Duration::from_millis(50)).await;

    let measurements = bme280.measure().unwrap();

    return Ok(WeatherState {
        humidity: measurements.humidity,
        temperature: measurements.temperature,
        pressure: measurements.pressure,
    });
}
