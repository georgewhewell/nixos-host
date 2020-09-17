use anyhow::Result;
use eeprom24x::Eeprom24x;
use linux_embedded_hal::I2cdev;
use log::info;
use pwm_pca9685::{Channel, OutputLogicState, Pca9685, SlaveAddr};
use serde::Serialize;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::time::{Duration, Instant};


use crate::mqtt::{MQTTDevice, MQTTSensorConfig, MQTTSwitchConfig};

#[derive(Debug, Serialize)]
pub enum PumpState {
    ON,
    OFF,
}

#[derive(Debug)]
struct WaterPump {
    current_state: PumpState,
    total_on: std::time::Duration,
    last_on: std::time::Instant,
}

#[derive(Debug)]
pub struct PumpStartCommand {
    pub motor: u32,
    pub time: u32,
}

fn get_channels(idx: usize) -> (Channel, Channel, Channel) {
    // https://github.com/friendlyarm/NanoHAT-Motor-Python-Library/blob/master/FriendlyELEC_NanoHatMotor/FriendlyELEC_NanoHatMotor.py#L174
    match idx {
        0 => (Channel::C0, Channel::C2, Channel::C1),
        1 => (Channel::C5, Channel::C4, Channel::C3),
        2 => (Channel::C15, Channel::C13, Channel::C14),
        3 => (Channel::C10, Channel::C11, Channel::C12),
        _ => (Channel::C0, Channel::C0, Channel::C0),
    }
}

pub struct PumpEvent {
    pub pump: u32,
    pub state: PumpState,
    pub total_seconds: u32,
}

pub struct PumpProxy {
    cmd_sender: Sender<PumpStartCommand>,
    evt_receiver: Receiver<PumpEvent>,
}

impl PumpProxy {
    pub fn new() -> Result<Self> {
        let (cmd_sender, cmd_receiver) = channel();
        let (evt_sender, evt_receiver) = channel();
        let mut pc = PumpController::new()?;

        std::thread::spawn(move || pc.run(cmd_receiver, evt_sender));

        Ok(PumpProxy {
            cmd_sender,
            evt_receiver,
        })
    }

    pub fn send(&self, cmd: PumpStartCommand) -> Result<()> {
        self.cmd_sender.send(cmd).map_err(|e| e.into())
    }

    pub fn try_recv(&mut self) -> Result<PumpEvent> {
        self.evt_receiver.try_recv().map_err(|err| err.into())
    }

    pub fn sensor_config(&self) -> Vec<MQTTSensorConfig> {
        (0..4)
            .map(|i| MQTTSensorConfig {
                name: format!("Pump {} Seconds", i),
                unique_id: format!("farmbot-pump-sensor{}", i),
                state_topic: format!("homeassistant/switch/farmbot/pump_{}/state", i),
                value_template: "{{ value_json.total_seconds }}".to_string(),
                unit_of_measurement: "seconds".to_string(),
                device_class: None,
                device: MQTTDevice {
                    identifiers: vec!["farmbot".to_string()],
                    connections: vec![],
                    manufacturer: "Whewell Comms".to_string(),
                    name: "Farmbot".to_string(),
                    model: "Farmbot 0.1".to_string(),
                },
            })
            .collect()
    }

    pub fn mqtt_config(&self) -> Vec<MQTTSwitchConfig> {
        (0..4)
            .map(|i| MQTTSwitchConfig {
                name: format!("Pump {}", i),
                unique_id: format!("farmbot-pump-{}", i),
                command_topic: format!("homeassistant/switch/farmbot/pump_{}/cmd", i),
                state_topic: format!("homeassistant/switch/farmbot/pump_{}/state", i),
                payload_on: "ON".to_string(),
                payload_off: "OFF".to_string(),
                value_template: "{{ value_json.state }}".to_string(),
                device: MQTTDevice {
                    identifiers: vec!["farmbot".to_string()],
                    connections: vec![],
                    manufacturer: "Whewell Comms".to_string(),
                    name: "Farmbot".to_string(),
                    model: "Farmbot 0.1".to_string(),
                },
            })
            .collect()
    }

    pub fn mqtt_subscribe(&self) -> Vec<String> {
        (0..4)
            .map(|i| format!("homeassistant/switch/farmbot/pump_{}/cmd", i))
            .collect()
    }
}

struct PumpController {
    pwm: Pca9685<I2cdev>,
    motors: Vec<WaterPump>,
}

impl PumpController {
    pub fn read_eeprom() -> Result<Vec<u32>> {
        let dev = I2cdev::new("/dev/i2c-0")?;
        let address = eeprom24x::SlaveAddr::Alternative(true, false, false);
        let mut eeprom = Eeprom24x::new_24x32(dev, address);

        let mut totals = vec![];
        for i in 0..4 {
            let mut buffer: [u8; 4] = [0; 4];
            eeprom.read_data(32 * i, &mut buffer).unwrap();
            let seconds = u32::from_le_bytes(buffer);
            info!("Read from {}: {:?} ({})", 32 * i, &buffer, &seconds);
            if seconds == u32::MAX {
                totals.push(0);
            } else {
                totals.push(seconds);
            }
        }
        Ok(totals)
    }

    pub fn write_eeprom(num: u32, seconds: u32) -> Result<()> {
        let dev = I2cdev::new("/dev/i2c-0")?;
        let address = eeprom24x::SlaveAddr::Alternative(true, false, false);
        let mut eeprom = Eeprom24x::new_24x32(dev, address);
        let buffer = seconds.to_le_bytes();
        eeprom.write_page(32 * num, &buffer).unwrap();
        Ok(())
    }

    pub fn run(&mut self, receiver: Receiver<PumpStartCommand>, sender: Sender<PumpEvent>) -> () {
        for msg in receiver.iter() {
            self.run_motor(msg, sender.clone());
        }
    }

    pub fn new() -> Result<Self> {
        info!("Reading eeprom");
        let seconds = match PumpController::read_eeprom() {
            Ok(seconds) => seconds,
            _ => vec![0, 0, 0, 0],
        };

        info!("Setting up Pca9685");
        let pwm = PumpController::get_pwm()?;
        let motors = (0..4)
            .map(|i| WaterPump {
                total_on: Duration::from_secs(seconds[i] as u64),
                current_state: PumpState::OFF,
                last_on: Instant::now(),
            })
            .collect();
        let pc = PumpController { pwm, motors };
        Ok(pc)
    }

    fn get_pwm() -> Result<Pca9685<I2cdev>> {
        let dev = I2cdev::new("/dev/i2c-0")?;
        let pwm = Pca9685::new(
            dev,
            SlaveAddr::Alternative(true, false, false, false, false, false),
        );
        Ok(pwm)
    }

    fn run_motor(&mut self, cmd: PumpStartCommand, sender: Sender<PumpEvent>) -> Result<()> {
        info!("Running pump {}", cmd.motor);

        sender.send(PumpEvent {
            pump: cmd.motor,
            state: PumpState::ON,
            total_seconds: self.motors[cmd.motor as usize].total_on.as_secs() as u32,
        });

        let (p1, p2, p3) = get_channels(cmd.motor as usize);

        self.pwm.set_channel_on_off(Channel::All, 0, 0).unwrap();
        self.pwm.set_prescale(26).unwrap();
        self.pwm
            .set_output_logic_state(OutputLogicState::Inverted)
            .unwrap();
        self.pwm.enable().unwrap();

        // Set FORWARD
        self.pwm.set_channel_full_on(p3, 0).unwrap();
        self.pwm.set_channel_full_off(p2).unwrap();

        // Set speed
        self.pwm.set_channel_off(p1, 0).unwrap();

        // Sleep
        std::thread::sleep(Duration::from_millis(cmd.time.into()));

        // Stop
        println!("Stopping {}", cmd.motor);
        self.pwm.set_channel_full_off(p1).unwrap();
        self.pwm.set_channel_full_off(p3).unwrap();
        self.pwm.disable().unwrap();

        let new_secs = self.motors[cmd.motor as usize].total_on.as_secs() as u32 + cmd.time / 1000;
        PumpController::write_eeprom(cmd.motor, new_secs);
        self.motors[cmd.motor as usize].total_on = Duration::from_secs(new_secs.into());

        sender.send(PumpEvent {
            pump: cmd.motor,
            state: PumpState::OFF,
            total_seconds: new_secs,
        });

        Ok(())
    }
}
