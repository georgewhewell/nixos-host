use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;

use anyhow::Result;
use log::{debug, info};
use rumqttc::{Client, MqttOptions, Packet, Publish, QoS};
use serde::Serialize;
use serde_json;

use crate::farmbot::pumps::PumpStartCommand;

pub enum MQTTPublish {
    SensorConfig {
        topic: String,
        payload: MQTTSensorConfig,
    },
    SwitchConfig {
        topic: String,
        payload: MQTTSwitchConfig,
    },
    DeviceState {
        topic: String,
        payload: serde_json::Value,
    },
    Subscribe {
        topic: String,
    },
}

pub enum MQTTCommand {
    PumpStartCommand { cmd: PumpStartCommand },
}

#[derive(Serialize, Clone)]
pub struct MQTTDevice {
    pub identifiers: Vec<String>,
    pub connections: Vec<[String; 2]>,
    pub manufacturer: String,
    pub name: String,
    pub model: String,
}

#[derive(Serialize, Clone)]
pub struct MQTTSensorConfig {
    pub name: String,
    pub unique_id: String,
    pub device: MQTTDevice,
    pub unit_of_measurement: String,
    pub value_template: String,
    pub state_topic: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_class: Option<String>,
}

#[derive(Serialize, Clone)]
pub struct MQTTSwitchConfig {
    pub name: String,
    pub unique_id: String,
    pub device: MQTTDevice,
    pub value_template: String,
    pub state_topic: String,
    pub command_topic: String,
    pub payload_on: String,
    pub payload_off: String,
}

pub struct MQTTConnection {
    pub sender: Sender<MQTTPublish>,
    pub receiver: Receiver<MQTTCommand>,
}

impl MQTTConnection {
    pub fn publish(&mut self, data: MQTTPublish) {
        self.sender.send(data);
    }

    pub fn new() -> Result<Self> {
        let mut mqttoptions = MqttOptions::new("farmbot", "192.168.23.5", 1883);
        mqttoptions.set_keep_alive(5);
        mqttoptions.set_credentials("rw", "");

        let (mut client, mut connection) = Client::new(mqttoptions, 10);
        let (sender, receiver) = channel();
        let _sender_1 = sender.clone();

        thread::spawn(move || {
            fn handle_publish(publish: Publish, sender: Sender<MQTTCommand>) {
                if publish.topic.ends_with("/cmd") {
                    if publish.payload == "ON" {
                        let pump = publish
                            .topic
                            .chars()
                            .find(|a| a.is_digit(10))
                            .and_then(|a| a.to_digit(10));
                        if let Some(pump_num) = pump {
                            info!("Turn on {}", pump_num);
                            sender.send(MQTTCommand::PumpStartCommand {
                                cmd: PumpStartCommand {
                                    motor: pump_num,
                                    time: 5000,
                                },
                            });
                        }
                    }
                }
            }

            for result in connection.iter() {
                match result {
                    Ok((Some(inc), _)) => {
                        match inc {
                            Packet::Publish(publish) => {
                                // Got subscription..
                                handle_publish(publish, sender.clone())
                            }
                            _ => {}
                        }
                    }
                    Ok((_, Some(_out))) => {
                        debug!("Outgoing message- why would i care!?!");
                    }
                    Ok((None, None)) => {}
                    Err(_) => {}
                }
            }
        });

        let (pub_sender, pub_receiver) = channel();
        thread::spawn(move || {
            // let sender_1 = sender.clone();
            for notification in pub_receiver.iter() {
                match notification {
                    MQTTPublish::SensorConfig { topic, payload } |
                    MQTTPublish::SwitchConfig { topic, payload } |
                    MQTTPublish::DeviceState { topic, payload } => {
                        client
                            .publish(
                                topic,
                                QoS::AtLeastOnce,
                                true,
                                serde_json::to_string(&payload).unwrap(),
                            )
                            .unwrap();
                    }
                    MQTTPublish::Subscribe { topic } => {
                        info!("Subscribing to: {}", topic);
                        client.subscribe(topic, QoS::AtMostOnce).unwrap();
                    }
                }
            }
        });

        Ok(MQTTConnection {
            sender: pub_sender,
            receiver,
        })
    }

    pub fn try_recv(&mut self) -> Result<MQTTCommand> {
        self.receiver.try_recv().map_err(|err| err.into())
    }
}
