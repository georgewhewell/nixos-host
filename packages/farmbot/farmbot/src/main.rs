use env_logger;
use log::debug;

mod config;
mod farmbot;
mod mqtt;

fn main() {
    env_logger::init();

    debug!("Reading config file");
    let config = config::get().expect("Error loading config file");

    let mut farmbot = farmbot::Farmbot::new(&config);
    farmbot.start_mqtt();
    farmbot.init_sensors();
    farmbot.start_btle();
    farmbot.run();
}
