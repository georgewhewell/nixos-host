use std::collections::HashMap;
use serde::Deserialize;
use anyhow::Result;
use std::fs;

#[derive(Deserialize)]
pub struct MifloraConfig {
    address: String,
    pump: Option<u8>,
}

#[derive(Deserialize)]
pub struct WeatherConfig {
    pub mqtt_hostname: String,
    pub mqtt_username: String,
    mifloras: HashMap<String, MifloraConfig>,
}

pub fn get() -> Result<WeatherConfig> {
    let config_str = fs::read_to_string("config.toml")?;
    let config: WeatherConfig = toml::from_str(&config_str)?;
    Ok(config)
}