use anyhow::Result;
use btleplug::api::BDAddr;

use log::{debug, info, warn};
use rand::Rng;
use serde_json::json;
use std::collections::HashMap;
use std::time::{Duration, Instant};

use crate::config::{FarmbotConfig, PlantConfig};
use crate::farmbot::btle::miflora::MifloraData;
use crate::farmbot::btle::BTLEListener;
use crate::farmbot::pumps::PumpStartCommand;
use crate::farmbot::tank::TankLevelSensor;
use crate::mqtt::{MQTTCommand, MQTTConnection, MQTTPublish};

mod btle;
pub mod pumps;
mod tank;
mod weather;

struct PlantState {
    name: String,
    config: PlantConfig,
    miflora: Option<MifloraData>,
    last_watered: Instant,
}

pub struct Farmbot {
    config: FarmbotConfig,
    plants: HashMap<BDAddr, PlantState>,

    tank: Option<tank::TankLevelSensor>,
    weather: Option<weather::WeatherSensor>,
    pumps: Option<pumps::PumpProxy>,
    btle: Option<BTLEListener>,
    mqtt: Option<MQTTConnection>,
}

impl Farmbot {
    pub fn new(config: &FarmbotConfig) -> Farmbot {
        let mut rng = rand::thread_rng();
        let plants = config
            .plants
            .iter()
            .map(|(name, config)| {
                (
                    config.bdaddr(),
                    PlantState {
                        name: name.to_string(),
                        config: config.clone(),
                        miflora: None,
                        last_watered: Instant::now() - Duration::from_secs(rng.gen_range(0, 120)),
                    },
                )
            })
            .collect();
        Farmbot {
            config: config.clone(),
            plants: plants,
            btle: None,
            mqtt: None,
            pumps: None,
            tank: None,
            weather: None,
        }
    }

    fn farm(&mut self) -> Result<()> {
        if self.config.farming_enabled == false {
            info!("Farming disabled, skipping");
            return Ok(());
        }

        if self.pumps.is_none() {
            warn!("no pumps, cannot farm");
            return Ok(());
        }

        if let Some(ref mut tank) = self.tank {
            if tank.get() > self.config.max_tank_level {
                warn!("Tank level is too high, skip farming");
                return Ok(());
            }
        } else {
            warn!("We dont know tank level, skip farming");
            return Ok(());
        }

        for (_bdaddr, plant) in self.plants.iter_mut() {
            if let Some(pump) = plant.config.pump {
                if let Some(miflora) = &plant.miflora {
                    let moist = miflora.moisture.unwrap(); // we check this earlier
                    if moist < self.config.target_moisture {
                        if plant.last_watered + Duration::from_secs(self.config.default_interval)
                            < Instant::now()
                        {
                            info!("we need to farm {}", plant.name);

                            if let Some(ref mut pumps) = self.pumps {
                                info!("Great! farming {}", plant.name);
                                plant.last_watered = Instant::now();
                                pumps.send(PumpStartCommand {
                                    motor: pump,
                                    time: self.config.watering_seconds * 1000,
                                });
                            }
                        } else {
                            info!("its too soon to farm {}", plant.name)
                        }
                    } else {
                        info!("Plant {} is wet", plant.name);
                    }
                } else {
                    info!("Plant {} has not data, will not farm", plant.name);
                }
            } else {
                info!("i have no pump, and i must farm {}", plant.name);
                continue;
            }
        }

        Ok(())
    }

    pub fn init_sensors(&mut self) -> Result<()> {
        if let Ok(tank) = tank::TankLevelSensor::new() {
            info!("Create TankSensor: {:?}", tank);
            self.send_mqtt(MQTTPublish::SensorConfig {
                topic: "homeassistant/sensor/farmbot/tank_level/config".to_string(),
                payload: tank.mqtt_config(),
            });
            self.tank = Some(tank);
        }

        if let Ok(weather) = weather::WeatherSensor::new() {
            info!("Create WeatherSensor: {:?}", weather);
            for msg in weather.mqtt_config().iter() {
                self.send_mqtt(MQTTPublish::SensorConfig {
                    topic: format!(
                        "homeassistant/sensor/farmbot/{}/config",
                        msg.unique_id.to_lowercase().replace(" ", "_")
                    ),
                    payload: msg.clone(),
                });
            }
            self.weather = Some(weather);
        }

        if let Ok(pc) = pumps::PumpProxy::new() {
            info!("Create PumpProxy");
            for msg in pc.mqtt_config().iter() {
                self.send_mqtt(MQTTPublish::SwitchConfig {
                    topic: format!(
                        "homeassistant/switch/farmbot/{}/config",
                        msg.name.to_lowercase().replace(" ", "_")
                    ),
                    payload: msg.clone(),
                });
            }

            for msg in pc.sensor_config().iter() {
                self.send_mqtt(MQTTPublish::SensorConfig {
                    topic: format!(
                        "homeassistant/sensor/farmbot/{}/config",
                        msg.name.to_lowercase().replace(" ", "_")
                    ),
                    payload: msg.clone(),
                });
            }

            for topic in pc.mqtt_subscribe().iter() {
                self.send_mqtt(MQTTPublish::Subscribe {
                    topic: topic.to_string(),
                });
            }

            self.pumps = Some(pc);
        }
        Ok(())
    }

    pub fn start_btle(&mut self) -> Result<()> {
        info!("Starting BTLE");
        let btle = BTLEListener::new(self.config.clone())?;
        self.btle = Some(btle);
        Ok(())
    }

    pub fn start_mqtt(&mut self) -> Result<()> {
        info!("Starting MQTT");
        let mqtt = MQTTConnection::new()?;
        self.mqtt = Some(mqtt);
        Ok(())
    }

    pub fn run(&mut self) -> Result<()> {
        info!("Running Farmbot");

        loop {
            let mut btle_data = vec![];
            if let Some(ref mut btle) = self.btle {
                while let Ok(data) = btle.try_recv() {
                    debug!("Got some data from BTLE!!");
                    btle_data.push(data);
                }
            }

            for data in btle_data {
                self.handle_miflora(data);
            }

            if let Some(ref mut mqtt) = self.mqtt {
                while let Ok(data) = mqtt.try_recv() {
                    match data {
                        MQTTCommand::PumpStartCommand { cmd } => {
                            if let Some(ref mut pc) = self.pumps {
                                pc.send(cmd);
                            }
                        }
                    }
                    debug!("Got some data from MQTT!!");
                }
            }

            self.read_sensors();

            self.farm();

            std::thread::sleep(Duration::from_millis(1000));
        }
    }

    fn send_mqtt(&mut self, announce: MQTTPublish) {
        if let Some(ref mut mqtt) = self.mqtt {
            mqtt.publish(announce);
        }
    }

    fn read_sensors(&mut self) -> Result<()> {
        debug!("Reading sensors");
        let mut datas = vec![];

        if let Some(ref mut pumps) = self.pumps {
            while let Ok(data) = pumps.try_recv() {
                debug!("Got some data from pumps!!");
                datas.push(MQTTPublish::DeviceState {
                    topic: format!("homeassistant/switch/farmbot/pump_{}/state", data.pump),
                    payload: json!({
                        "state": data.state,
                        "total_seconds": data.total_seconds,
                    }),
                })
            }
        }

        if let Some(ref mut tank) = self.tank {
            if tank.should_read() {
                datas.push(MQTTPublish::DeviceState {
                    topic: "homeassistant/sensor/farmbot/tank_level/state".to_string(),
                    payload: TankLevelSensor::mqtt_state(tank.read()?),
                });
            }
        }

        if let Some(ref mut weather) = self.weather {
            if weather.should_read() {
                if let Ok(reading) = weather.mqtt_state() {
                    datas.push(MQTTPublish::DeviceState {
                        topic: "homeassistant/sensor/farmbot/weather/state".to_string(),
                        payload: reading,
                    });
                }
            }
        }

        for data in datas.drain(..) {
            self.send_mqtt(data);
        }

        Ok(())
    }

    fn handle_miflora(&mut self, message: MifloraData) -> Result<()> {
        debug!("Data: {:?}", message);
        let mut msgs = vec![];
        match self.plants.get_mut(&message.bdaddr) {
            Some(plant) => {
                let plant_name = plant.name.clone();
                debug!("Got plant data for {}", plant_name);
                if plant.miflora.is_none() {
                    info!("Sending MQTT config for new plant: {}", plant_name);
                    for announce in message.get_config(&plant_name).iter() {
                        msgs.push(MQTTPublish::SensorConfig {
                            topic: format!(
                                "homeassistant/sensor/farmbot/{}/config",
                                announce.name.to_lowercase().replace(" ", "_")
                            ),
                            payload: announce.clone(),
                        });
                    }
                }
                plant.miflora = Some(message.clone());
                msgs.push(MQTTPublish::DeviceState {
                    topic: format!("homeassistant/sensor/farmbot/{}/state", plant_name),
                    payload: message.mqtt_state(),
                });
            }
            None => {
                warn!("Unknown plant :S");
            }
        };

        for msg in msgs.drain(..) {
            self.send_mqtt(msg);
        }

        Ok(())
    }
}
