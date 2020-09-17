use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Mutex;
use std::thread;
use std::time::Duration;

use anyhow::Result;
use btleplug;
use btleplug::api::Central;
use btleplug::bluez::manager::Manager;
use btleplug::bluez::protocol::hci::LEAdvertisingData;
use log::{info, warn};

use crate::farmbot::btle::miflora::{MifloraData, MifloraListenerState};

use crate::config::FarmbotConfig;

pub mod miflora;

pub struct BTLEListener {
    receiver: Receiver<MifloraData>,
    handle: std::thread::JoinHandle<()>,
}

impl BTLEListener {
    pub fn new(config: FarmbotConfig) -> Result<BTLEListener> {
        let (sender, receiver) = channel();
        let handle = thread::spawn(move || {
            _listen(config, sender.clone());
        });
        Ok(BTLEListener {
            receiver: receiver,
            handle: handle,
        })
    }

    pub fn try_recv(&mut self) -> Result<MifloraData> {
        self.receiver.try_recv().map_err(|err| err.into())
    }
}

fn _listen(_config: FarmbotConfig, sender: Sender<MifloraData>) {
    info!("Hello! I am PLANT LISTENER");
    let manager = Manager::new().unwrap();

    // get the first bluetooth adapter
    let adapters = manager.adapters().unwrap();
    let mut adapter = adapters.into_iter().nth(0).unwrap();

    // reset the adapter -- clears out any errant state
    adapter = manager.down(&adapter).unwrap();
    adapter = manager.up(&adapter).unwrap();

    // connect to the adapter
    let central = adapter.connect().unwrap();

    let floradata = Mutex::new(MifloraListenerState::new());

    central.on_event(Box::new(
        move |event: btleplug::api::CentralEvent<'_>| match event {
            btleplug::api::CentralEvent::DeviceUpdated(addr, data) => {
                if addr.to_string().starts_with("C4:7C:8D") {
                    for x in data {
                        match x {
                            LEAdvertisingData::Flags(_a) => (),
                            LEAdvertisingData::ServiceClassUUID16(_a) => (),
                            LEAdvertisingData::ServiceData16(65173, b) => {
                                floradata.lock().unwrap().apply(b, sender.clone());
                            }
                            any => {
                                warn!("BTLE: Adver data not understand! {:?}", any);
                            }
                        }
                    }
                }
            }
            _ => (),
        },
    ));

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
