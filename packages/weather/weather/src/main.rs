use async_channel;
use std::time::Duration;
use tokio::task;
use tokio::time;
use serde_json::json;
use crate::sensors::listen;
use crate::mqtt::{connect, SensorUpdate};
use futures::{
    future::FutureExt, // for `.fuse()`
    pin_mut,
    select,
};
use async_channel::{Receiver, Sender};

mod http;
mod mqtt;
mod pumps;
mod tank;
mod weather;
mod sensors;
mod config;
mod arduino;

static SENSOR_PREFIX: &str = "home-assistant";

trait Sensor {
    fn config(prefix: &str) -> serde_json::value::Value;
    fn reading(&Self) -> f32;
}

trait Switch {
    fn config(prefix: &str) -> serde_json::value::Value;
}

trait Peripheral {
    pub fn sensors(&Self) -> &[Sensor]
    pub fn switches(&Self) -> &[Switch]
}

#[tokio::main]
async fn main() {

    println!("Reading config file");
    let settings = config::get().expect("Error loading config file");

    let (http_s, http_r) = async_channel::unbounded();
    let (http_s1, http_r1) = (http_s.clone(), http_r.clone());

    task::spawn(
        http::serve(
            http_s1,
        ),
    );

    let (mqtt_sub_s, mqtt_sub_r) = async_channel::unbounded();
    let (mqtt_sub_s1, mqtt_sub_r1) = (mqtt_sub_s.clone(), mqtt_sub_r.clone());
    let (mqtt_pub_s, mqtt_pub_r) = async_channel::unbounded();
    let (mqtt_pub_s1, mqtt_pub_r1) = (mqtt_pub_s.clone(), mqtt_pub_r.clone());
    task::spawn(
        mqtt::connect(
            settings.mqtt_hostname,
            settings.mqtt_username,
            mqtt_sub_s1,
            mqtt_pub_r1,
            vec![
                format!("{}/switch/pumps/pump0/cmd", SENSOR_PREFIX),
                format!("{}/switch/pumps/pump1/cmd", SENSOR_PREFIX),
                format!("{}/switch/pumps/pump2/cmd", SENSOR_PREFIX),
                format!("{}/switch/pumps/pump3/cmd", SENSOR_PREFIX),
            ],
        )
    );

    let (miflora_s, miflora_r) = async_channel::unbounded();
    let (miflora_s1, miflora_r1) = (miflora_s.clone(), miflora_r.clone());
    listen(
        miflora_s1,
    );

    mqtt_pub_s.send(SensorUpdate {
        topic: format!("{}/sensor/weather/config", SENSOR_PREFIX),
        message: weather::config().to_string(),
    })
    .await
    .unwrap();

    for i in [
        weather::TemperatureSensor,
        weather::PressureSensor,
        weather::HumiditySensor,
    ] {
        mqtt_pub_s.send(SensorUpdate {
            topic: format!("{}/switch/pumps/pump{}/config", SENSOR_PREFIX, i),
            message: i.config(SENSOR_PREFIX.to_string()).to_string(),
        })
        .await
        .unwrap();
    }

    mqtt_pub_s.send(SensorUpdate {
        topic: format!("{}/sensor/water_tank/config", SENSOR_PREFIX),
        message: tank::config().to_string(),
    })
    .await
    .unwrap();

    mqtt_pub_s.send(SensorUpdate {
        topic: format!("{}/switch/pumps/config", SENSOR_PREFIX),
        message: pumps::config(SENSOR_PREFIX.to_string()).to_string(),
    })
    .await
    .unwrap();

    for i in 0..4 {
        mqtt_pub_s.send(SensorUpdate {
            topic: format!("{}/switch/pumps/pump{}/config", SENSOR_PREFIX, i),
            message: pumps::pump_config(SENSOR_PREFIX.to_string(), i).to_string(),
        })
        .await
        .unwrap();
    }

    println!("Seup complete");
    // let run = pumps::run_all().await;
    // println!("finished spin test: {:?}", run);
    let next_tick = time::delay_for(Duration::from_millis(500)).await;

    loop {
        let weather = weather::read_weather().await;
        mqtt_pub_s.send(SensorUpdate {
            topic: format!("{}/sensor/weather/state", SENSOR_PREFIX),
            message: json!({
                "temperature": weather.temperature,
                "pressure": weather.pressure,
                "humidity": weather.humidity,
            })
            .to_string(),
        })
        .await
        .unwrap();

        println!("send weather update: {:?}", weather);

        // //
        let tank_level = tank::read_tank_level();
        mqtt_pub_s.send(mqtt::SensorUpdate{
            topic: format!("{}/sensor/water_tank/state", SENSOR_PREFIX),
            message: json!({
                "water_level": tank_level,
            }).to_string(),
        }).await
        .unwrap();

        println!("send tank update: {:?}", tank_level);

        time::delay_for(Duration::from_millis(50)).await;

        let next_tick = time::delay_for(Duration::from_millis(5000)).fuse();
        let read_msg = mqtt_sub_r1.recv().fuse();
        let read_http_msg = http_r1.recv().fuse();
        let read_miflora_msg = miflora_r1.recv().fuse();

        pin_mut!(next_tick, read_msg, read_http_msg, read_miflora_msg);

        select! {
            a = next_tick => {
                println!("nothing happen.. tick tock..");
            }
            b = read_msg => {
                println!("got msg from mqtt: {:?}", b)
            }
            c = read_http_msg => {
                println!("got http message");
                match c {
                    Ok(num) => {
                        // println!("I am going to start motor {}", num.motor);
                        pumps::run_motor(num).await;
                    },
                    Err(_) => println!("Error from http")
                }
            }
            d = read_miflora_msg => {
                println!("got miflora message!");
            }
        };
    }
}
