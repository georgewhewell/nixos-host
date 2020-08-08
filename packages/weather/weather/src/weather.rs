use bme280::BME280;
use linux_embedded_hal::{Delay, I2cdev};
use serde::Serialize;
use shared_bus;
use std::{
    thread,
    time::Duration,
};

#[derive(Serialize)]
pub struct WeatherState {
    humidity: f32,
    temperature: f32,
    pressure: f32,
}

pub fn read_weather() -> WeatherState {
    println!("Reading weather!");
    let i2c_bus = I2cdev::new("/dev/i2c-0").unwrap();
    let manager = shared_bus::BusManager::<std::sync::Mutex<_>, _>::new(i2c_bus);
    let mut bme280 = BME280::new_primary(manager.acquire(), Delay);

    bme280.init().unwrap();
    thread::sleep(Duration::from_millis(50));

    let measurements = bme280.measure().unwrap();

    return WeatherState{
        humidity: measurements.humidity,
        temperature: measurements.temperature,
        pressure: measurements.pressure,
    };
}