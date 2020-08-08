use async_channel::{Receiver, Sender};
use futures::{
    future::FutureExt, // for `.fuse()`
    pin_mut,
    select,
};
use mqtt_async_client::{
    client::{
        Client,
        Publish,
        QoS,
        Subscribe,
        SubscribeTopic,
    },
};
use std::{
    fmt::Debug,
};
use tokio::{
    self,
    time::{
        Duration,
    },
};

#[derive(Debug)]
pub struct SensorUpdate {
    pub topic: String,
    pub message: String,
}


pub async fn connect(
    sender: Sender<SensorUpdate>,
    receiver: Receiver<SensorUpdate>
) {

    println!("I am connecting!");
    let mut client = Client::builder()
        .set_host("192.168.23.5".to_owned())
        .set_port(1883)
        .set_username(Some("rw".to_string()))
        .set_connect_retry_delay(Duration::from_secs(1))
        .build().unwrap();
    client.connect().await.unwrap();

    // Subscribe
    let subopts = Subscribe::new(vec![
        SubscribeTopic {
            qos: QoS::AtMostOnce,
            topic_path: "#".to_owned()
        }
    ]);

    let subres = client.subscribe(subopts).await.unwrap();
    subres.any_failures().unwrap();

    // Publish
    let mut p = Publish::new(
        "some topic".to_owned(),
        "some message".as_bytes().to_vec()
    );
    p.set_qos(QoS::AtMostOnce);
    client.publish(&p).await.unwrap();

    loop {

        println!("Checking for new messages..");

        let read_subs = client.read_subscriptions().fuse();
        let read_msg = receiver.recv().fuse();
        pin_mut!(read_subs, read_msg);

        select! {
            a = read_subs => {
                println!("Got a message from mqtt: {:?}", a);
            },
            b = read_msg => {
                println!("Got a message from receiver: {:?}", b);
                client.publish(&p).await.unwrap();
            },
        }

    }

}
