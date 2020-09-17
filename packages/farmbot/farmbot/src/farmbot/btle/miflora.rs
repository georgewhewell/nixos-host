use std::cmp::PartialEq;
use std::collections::HashMap;
use std::sync::mpsc::Sender;

use anyhow::Result;
use btleplug::api::BDAddr;
use serde_json::json;
use titlecase::titlecase;

use crate::mqtt::{MQTTDevice, MQTTSensorConfig};

#[derive(Debug, PartialEq, Clone)]
pub enum XiomiDevice {
    Miflora,
    Unknown,
}

#[derive(Clone, Debug, PartialEq)]
pub struct MifloraData {
    pub device: XiomiDevice,
    pub bdaddr: BDAddr,
    pub conductivity: Option<u16>,
    pub moisture: Option<u16>,
    pub temperature: Option<f32>,
    pub illuminance: Option<u16>,
}

impl MifloraData {
    fn populated(&self) -> bool {
        self.conductivity.is_some()
            && self.moisture.is_some()
            && self.temperature.is_some()
            && self.illuminance.is_some()
    }

    fn get_mqtt_config(
        &self,
        name: &str,
        suffix: String,
        unit_of_measurement: String,
        device_class: Option<String>,
    ) -> MQTTSensorConfig {
        MQTTSensorConfig {
            name: format!("{} {}", titlecase(name), titlecase(&suffix)),
            unique_id: format!("{}-{}", name, suffix),
            unit_of_measurement: unit_of_measurement,
            device_class: device_class,
            state_topic: format!("homeassistant/sensor/farmbot/{}/state", name),
            value_template: format!("{{{{ value_json.{} }}}}", suffix),
            device: MQTTDevice {
                identifiers: vec![format!("miflora-{}", self.bdaddr)],
                connections: vec![["mac".to_string(), format!("{}", self.bdaddr)]],
                manufacturer: "Xiaomi".to_string(),
                name: titlecase(name),
                model: "MiFlora Plant Sensor (HHCCJCY01)".to_string(),
            },
        }
    }

    pub fn get_config(&self, name: &str) -> Vec<MQTTSensorConfig> {
        vec![
            self.get_mqtt_config(
                name,
                "light".to_string(),
                "lux".to_string(),
                Some("illuminance".to_string()),
            ),
            self.get_mqtt_config(
                name,
                "temperature".to_string(),
                "°C".to_string(),
                Some("temperature".to_string()),
            ),
            self.get_mqtt_config(
                name,
                "moisture".to_string(),
                "%".to_string(),
                Some("humidity".to_string()),
            ),
            self.get_mqtt_config(name, "conductivity".to_string(), "µS/cm".to_string(), None),
        ]
    }

    pub fn mqtt_state(&self) -> serde_json::Value {
        json!({
            "light": self.illuminance,
            "moisture": self.moisture,
            "conductivity": self.conductivity,
            "temperature": self.temperature,
        })
    }
}
#[derive(Debug)]
pub struct MifloraListenerState {
    last_data: HashMap<BDAddr, MifloraData>,
}

impl MifloraListenerState {
    pub fn new() -> Self {
        MifloraListenerState {
            last_data: HashMap::new(),
        }
    }
}

fn update_state(old: &MifloraData, new: &MifloraData) -> MifloraData {
    MifloraData {
        bdaddr: new.bdaddr.clone(),
        device: new.device.clone(),
        conductivity: new.conductivity.or(old.conductivity),
        moisture: new.moisture.or(old.moisture),
        temperature: new.temperature.or(old.temperature),
        illuminance: new.illuminance.or(old.illuminance),
    }
}

fn parse_xiaomi_announce(data: &Vec<u8>) -> MifloraData {
    let device_type = match &data[2..4] {
        [152, 0] => XiomiDevice::Miflora,
        _ => XiomiDevice::Unknown,
    };

    let mut address: [u8; 6] = [0, 0, 0, 0, 0, 0];
    address.copy_from_slice(&data[5..11]);

    let mut builder = MifloraData {
        device: device_type.clone(),
        bdaddr: BDAddr { address },
        conductivity: None,
        moisture: None,
        temperature: None,
        illuminance: None,
    };

    let end = data.len();
    let mut cursor: usize = 12;

    while cursor <= (end - 4) {
        let xval_type = &data[(cursor)..(cursor + 2)];
        let xval_leng = &data[(cursor + 2)];

        let xnext_point = cursor + 3 + *xval_leng as usize;
        let xval_data = &data[(cursor + 3)..xnext_point];

        match xval_type {
            [8, 16] => {
                builder.moisture = Some(xval_data[0] as u16);
            }
            [9, 16] => {
                builder.conductivity = Some((xval_data[0] as u16) | ((xval_data[1] as u16) << 8));
            }
            [7, 16] => {
                builder.illuminance = Some((xval_data[0] as u16) | ((xval_data[1] as u16) << 8));
            }
            [4, 16] => {
                builder.temperature =
                    Some(((xval_data[0] as u16) | ((xval_data[1] as u16) << 8)) as f32 / 10.0);
            }
            z => {
                panic!("watf is {:?}", z);
            }
        }
        // Try parse
        cursor = xnext_point
    }

    builder
}

impl MifloraListenerState {
    pub fn apply(&mut self, data: &Vec<u8>, sender: Sender<MifloraData>) -> Result<()> {
        let new_data = parse_xiaomi_announce(data);
        let bdaddr = new_data.bdaddr.clone();
        let merged = match self.last_data.get(&bdaddr) {
            Some(old_data) => update_state(&old_data, &new_data),
            None => new_data,
        };

        self.last_data.insert(bdaddr, merged.clone());
        if merged.populated() {
            sender.send(merged);
        }
        return Ok(());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_moisture() {
        let data: Vec<u8> = vec![
            113, 32, 152, 0, 131, 163, 170, 101, 141, 124, 196, 13, 8, 16, 1, 1,
        ];
        assert_eq!(
            parse_xiaomi_announce(&data),
            MifloraData {
                device: XiomiDevice::Miflora,
                bdaddr: BDAddr {
                    address: [163, 170, 101, 141, 124, 196]
                },
                conductivity: None,
                moisture: Some(1),
                temperature: None,
                illuminance: None,
            }
        );
    }

    #[test]
    fn test_extract_conductivity() {
        let data: Vec<u8> = vec![
            113, 32, 152, 0, 131, 163, 170, 101, 141, 124, 196, 13, 9, 16, 2, 0, 0,
        ];
        assert_eq!(
            parse_xiaomi_announce(&data),
            MifloraData {
                device: XiomiDevice::Miflora,
                bdaddr: BDAddr {
                    address: [163, 170, 101, 141, 124, 196]
                },
                conductivity: Some(0),
                moisture: None,
                temperature: None,
                illuminance: None,
            }
        );
    }

    #[test]
    fn test_extract_temperature() {
        let data: Vec<u8> = vec![
            113, 32, 152, 0, 131, 163, 170, 101, 141, 124, 196, 13, 4, 16, 2, 76, 1,
        ];
        assert_eq!(
            parse_xiaomi_announce(&data),
            MifloraData {
                device: XiomiDevice::Miflora,
                bdaddr: BDAddr {
                    address: [163, 170, 101, 141, 124, 196]
                },
                conductivity: None,
                moisture: None,
                illuminance: None,
                temperature: Some(33.2),
            }
        );
    }

    #[test]
    fn test_extract_illuminance() {
        let data: Vec<u8> = vec![
            113, 32, 152, 0, 78, 163, 170, 101, 141, 124, 196, 13, 7, 16, 3, 201, 1, 0,
        ];
        assert_eq!(
            parse_xiaomi_announce(&data),
            MifloraData {
                device: XiomiDevice::Miflora,
                bdaddr: BDAddr {
                    address: [163, 170, 101, 141, 124, 196]
                },
                conductivity: None,
                moisture: None,
                illuminance: Some(457),
                temperature: None,
            }
        );
    }
}
