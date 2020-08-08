use async_channel;
use std::time::Duration;
use tokio::task;
use tokio::time;

use crate::mqtt::connect;

mod mqtt;
mod weather;
mod tank;

#[tokio::main]
async fn main() {
    let (s, r) = async_channel::unbounded();
    let (s1, r1) = (s.clone(), r.clone());

    task::spawn(connect(s1, r1));

    loop {

        let weather = weather::read_weather();
        s.send(mqtt::SensorUpdate{
            topic: "weather".to_string(),
            message: serde_json::to_string(&weather).unwrap()
        });

        let tank = tank::read_tank_level();
        s.send(mqtt::SensorUpdate{
            topic: "tank_level".to_string(),
            message: serde_json::to_string(&tank).unwrap()
        });

        time::delay_for(Duration::from_millis(1000)).await;
    }

}
