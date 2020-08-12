extern crate pwm_pca9685 as pca9685;

use linux_embedded_hal::{I2cdev};
use pca9685::{Channel, Pca9685};
use tokio::time::{delay_for, Duration};
use serde_json::{json};



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

pub fn config(prefix: String) -> serde_json::value::Value {
    json!({
        "name": format!("{}/pumps", prefix),
        "platform": "farmbot"
    })
}

pub fn pump_config(prefix: String, num: usize) -> serde_json::value::Value {
    let cmd_topic = format!("{}/switch/pumps/pump{}/cmd", prefix, num);
    json!({
        "name": format!("pump{}", num),
        "device_class": "switch",
        "platform": "farmbot",
        "command_topic": cmd_topic,
        "payload_on": "START",
        "payload_off": "STOP",
        "value_template": "{{value_json['state']}}",
        "unique_id": format!("pump_{}", num),
    })
}

pub async fn run_motor(cmd: PumpStartCommand) {
    println!("Testing motor {}", cmd.motor);
    let dev = I2cdev::new("/dev/i2c-0").unwrap();
    let mut pwm = Pca9685::new(
        dev,
        pca9685::SlaveAddr::Alternative(true, false, false, false, false, false)
    );

    pwm.set_channel_on_off(Channel::All, 0, 0).unwrap();
    pwm.set_prescale(26).unwrap();
    pwm.enable().unwrap();

    let (p1, p2, p3) = get_channels(cmd.motor as usize);

    println!("Setting output mode");
    pwm.set_output_logic_state(pca9685::OutputLogicState::Inverted).unwrap();

    println!("Setting FORWARD");

    // Set FORWARD
    pwm.set_channel_full_on(p3, 0).unwrap();
    pwm.set_channel_full_off(p2).unwrap();

    // Set speed
    pwm.set_channel_off(p1, 0).unwrap();

    delay_for(Duration::from_millis(cmd.time as u64)).await;
    println!("Stopping {}", cmd.motor);

    pwm.set_channel_full_off(Channel::All).unwrap();

    println!("Disable and destroy");
    pwm.disable().unwrap();
    pwm.destroy();
}

pub async fn run_all() {
    for i in 0..4 {
        run_motor(PumpStartCommand { motor: i as u32, time: 500 }).await
    }
}
