use btleplug;

use crate::mqtt::{SensorUpdate};
use btleplug::bluez::manager::Manager;
use btleplug::api::{Central, BDAddr};

use btleplug::bluez::protocol::hci::LEAdvertisingData;
use async_channel::{Sender};

use std::time::{Duration};
use std::cmp::PartialEq;


#[derive(Debug, PartialEq, Clone)]
pub enum XiomiDevice {
    Miflora,
    Unknown,
}

#[derive(Debug, PartialEq)]
pub enum XiaomiReading {
    Temperature,
    Unknown,
}

#[derive(Debug, PartialEq)]
pub struct XiaomiData {
    pub device: XiomiDevice,
    pub bdaddr: BDAddr,
    pub conductivity: Option<u16>,
    pub moisture: Option<u16>,
    pub temperature: Option<f32>,
    pub illuminance: Option<u16>,
}


#[cfg(test)]
mod tests{
    use super::*;

    #[test]
    fn test_extract_moisture(){
        let data: Vec<u8> = vec![113, 32, 152, 0, 131, 163, 170, 101, 141, 124, 196, 13, 8, 16, 1, 1];
        assert_eq!(parse_xiaomi_announce(&data), XiaomiData {
            device: XiomiDevice::Miflora,
            bdaddr: BDAddr{ address: [163, 170, 101, 141, 124, 196] },
            conductivity: None,
            moisture: Some(1),
            temperature: None,
            illuminance: None,
        });
    }

    #[test]
    fn test_extract_conductivity(){
        let data: Vec<u8> = vec![113, 32, 152, 0, 131, 163, 170, 101, 141, 124, 196, 13, 9, 16, 2, 0, 0];
        assert_eq!(parse_xiaomi_announce(&data), XiaomiData {
            device: XiomiDevice::Miflora,
            bdaddr: BDAddr{ address: [163, 170, 101, 141, 124, 196] },
            conductivity: Some(0),
            moisture: None,
            temperature: None,
            illuminance: None,
        });
    }

    #[test]
    fn test_extract_temperature(){
        let data: Vec<u8> = vec![113, 32, 152, 0, 131, 163, 170, 101, 141, 124, 196, 13, 4, 16, 2, 76, 1];
        assert_eq!(parse_xiaomi_announce(&data), XiaomiData {
            device: XiomiDevice::Miflora,
            bdaddr: BDAddr{ address: [163, 170, 101, 141, 124, 196] },
            conductivity: None,
            moisture: None,
            illuminance: None,
            temperature: Some(33.2),
        });
    }

    #[test]
    fn test_extract_illuminance(){
    let data: Vec<u8> = vec![113, 32, 152, 0, 78, 163, 170, 101, 141, 124, 196, 13, 7, 16, 3, 201, 1, 0];
        assert_eq!(parse_xiaomi_announce(&data), XiaomiData {
            device: XiomiDevice::Miflora,
            bdaddr: BDAddr{ address: [163, 170, 101, 141, 124, 196] },
            conductivity: None,
            moisture: None,
            illuminance: Some(457),
            temperature: None,
        });
    }
}

pub fn parse_xiaomi_announce(data: &Vec<u8>) -> XiaomiData{
    let device_type = match &data[2..4] {
        [152, 0] => XiomiDevice::Miflora,
        _ => XiomiDevice::Unknown
    };

    let mut address: [u8; 6] = [0, 0, 0, 0, 0, 0];
    address.copy_from_slice(&data[5..11]);

    let mut builder = XiaomiData {
        device: device_type.clone(),
        bdaddr: BDAddr{ address },
        conductivity: None,
        moisture: None,
        temperature: None,
        illuminance: None,
    };

    let end = data.len();
    let mut cursor: usize = 12;

    while cursor <= (end - 4) {
        let xval_type = &data[(cursor)..(cursor+2)];
        let xval_leng = &data[(cursor+2)];

        let xnext_point = cursor + 3 + *xval_leng as usize;
        let xval_data = &data[(cursor + 3)..xnext_point];

        match xval_type {
            [8, 16] => {
                builder.moisture = Some(xval_data[0] as u16);
            },
            [9, 16] => {
                builder.conductivity = Some(
                    (xval_data[0] as u16) | ((xval_data[1] as u16) << 8)
                );
            },
            [7, 16] => {
                builder.illuminance = Some(
                    (xval_data[0] as u16) | ((xval_data[1] as u16) << 8)
                );
            },
            [4, 16] => {
                builder.temperature = Some(
                    ((xval_data[0] as u16) | ((xval_data[1] as u16) << 8)) as f32 / 10.0
                );
            },
            z => {
                panic!("watf is {:?}", z);
            }
        }
        // Try parse
        cursor = xnext_point
    }

    // let reading = match(&data[11]) {
    //     0x0D => {
    //         parse_temp(&data[11..16]);
    //         XiaomiReading::Temperature
    //     },
    //     _ => {
    //         println!("Dont know what measure: {:x?}", &data[11]);
    //         XiaomiReading::Unknown
    //     }
    // };

    // let length = &data[13]) {
    // }
    // for i in &mut address {
    //     address[*i as usize] = data[(16 - i) as usize]
    // };
    builder
}

pub async fn listen(
    sender: Sender<XiaomiData>,
) {
    println!("Hello! I am PLANT LISTENER");
    let manager = Manager::new().unwrap();

    // get the first bluetooth adapter
    let adapters = manager.adapters().unwrap();
    let mut adapter = adapters.into_iter().nth(0).unwrap();

    // reset the adapter -- clears out any errant state
    adapter = manager.down(&adapter).unwrap();
    adapter = manager.up(&adapter).unwrap();

    // connect to the adapter
    let central = adapter.connect().unwrap();

    central.on_event(Box::new(move |event: btleplug::api::CentralEvent| {
        match event {
            btleplug::api::CentralEvent::DeviceUpdated(addr, data) => {
                if addr.to_string().starts_with("C4:7C:8D") {
                    for x in data {
                        match x {
                            LEAdvertisingData::Flags(_a) => (),
                            LEAdvertisingData::ServiceClassUUID16(_a) => (),
                            LEAdvertisingData::ServiceData16(65173, b) => {
                                let parsed = parse_xiaomi_announce(b);
                                // let a = parse_mijia_bt_data(b);
                                sender.send(parsed).await;
                                println!("parsed: {:?} ", parsed);
                            },
                            any => {
                                println!("Adver data not understand! {:?}", any);
                            },

                        }
                    }

                }
            },
            _ => ()
        }
    }));

    // Passive scan
    central.active(false);

    // Don't filter duplicates
    central.filter_duplicates(false);

    // start scanning for devices
    central.start_scan().unwrap();

    loop {
        std::thread::sleep(Duration::from_millis(1000));
    }
}