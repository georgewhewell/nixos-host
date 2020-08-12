use async_channel::{Receiver, Sender};
use futures::{
    future::FutureExt, // for `.fuse()`
    pin_mut,
    select,
};
use mqtt_async_client::client::{Client, Publish, QoS, Subscribe, SubscribeTopic};
use std::fmt::Debug;
use tokio::{self, time::Duration};
use crate::pumps::PumpStartCommand;

#[derive(Debug)]
pub struct SensorUpdate {
    pub topic: String,
    pub message: String,
}

pub trait MQTTCommand {

}

async fn write(client: &Client, topic: String, payload: String) {
    // Publish
    let mut p = Publish::new(topic.to_owned(), payload.as_bytes().to_vec());
    p.set_qos(QoS::AtMostOnce);
    client.publish(&p).await.unwrap();
}

pub async fn connect(
    mqtt_hostname: String,
    mqtt_username: String,
    _sender: Sender<PumpStartCommand>,
    receiver: Receiver<SensorUpdate>,
    topics: Vec<String>,
) {
    println!("I am connecting!");
    let mut client_read = Client::builder()
        .set_host(mqtt_hostname.to_owned())
        .set_port(1883)
        .set_username(Some(mqtt_username.to_string()))
        .set_connect_retry_delay(Duration::from_secs(1))
        .build()
        .unwrap();
    client_read.connect().await.unwrap();

    let mut client_publish = Client::builder()
        .set_host(mqtt_hostname.to_owned())
        .set_port(1883)
        .set_username(Some(mqtt_username.to_string()))
        .set_connect_retry_delay(Duration::from_secs(1))
        .build()
        .unwrap();
    client_publish.connect().await.unwrap();

    // Subscribe
    let subopts = topics
        .into_iter()
        .map(|sub| SubscribeTopic {
            qos: QoS::AtMostOnce,
            topic_path: sub.to_owned(),
        })
        .collect::<Vec<_>>();

    let subres = client_read
        .subscribe(Subscribe::new(subopts))
        .await
        .unwrap();
    subres.any_failures().unwrap();

    loop {
        println!("Checking for new messages..");
        let read_subs = client_read.read_subscriptions().fuse();
        let read_msg = receiver.recv().fuse();
        pin_mut!(read_subs, read_msg);

        select! {
            a = read_subs => {
                println!("MQTT: Got a message from mqtt: {:?}", a);
                // write(client_publish, )
            },
            b = read_msg => {
                match (b) {
                    Ok(msg) => {
                        println!("MQTT: Got a message from receiver: {:?}", msg);
                        write(&client_publish, msg.topic, msg.message).await;
                    },
                    Err(_) => {
                        println!("MQTT Read Error");
                    }
                }
            },
        }
    }
}
