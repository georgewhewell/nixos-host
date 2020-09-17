use anyhow::Result;
use btleplug::api::BDAddr;
use serde::Deserialize;
use serde_hex::{SerHex, StrictPfx};
use std::collections::HashMap;
use std::fs;

#[derive(Deserialize, Clone)]
pub struct PlantConfig {
    #[serde(with = "SerHex::<StrictPfx>")]
    address: [u8; 6],
    pub pump: Option<u32>,
}

impl PlantConfig {
    pub fn bdaddr(&self) -> BDAddr {
        let mut cloned = self.address.clone();
        cloned.reverse();
        BDAddr { address: cloned }
    }
}

fn mqtt_prefix() -> String {
    "home_assistant/".to_string()
}

#[derive(Deserialize, Clone)]
pub struct FarmbotConfig {
    pub mqtt_hostname: String,
    pub mqtt_username: String,

    #[serde(default = "mqtt_prefix")]
    pub mqtt_prefix: String,

    pub plants: HashMap<String, PlantConfig>,

    pub farming_enabled: bool,
    pub max_tank_level: u16,
    pub target_moisture: u16,
    pub default_interval: u64,
    pub watering_seconds: u32,
}

pub fn get() -> Result<FarmbotConfig> {
    let config_str = fs::read_to_string("config.toml")?;
    let config: FarmbotConfig = toml::from_str(&config_str)?;
    Ok(config)
}
