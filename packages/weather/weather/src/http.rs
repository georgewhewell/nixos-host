use async_channel::{Sender};
use std::convert::Infallible;
use warp::{Filter, http::StatusCode, Rejection, Reply};

use crate::pumps::PumpStartCommand;


type Result<T> = std::result::Result<T, Rejection>;


pub async fn motor_handler(
    motor: u32,
    time: u32,
    sender: Sender<PumpStartCommand>
) -> Result<impl Reply> {
    sender.send(PumpStartCommand{motor: motor, time: time }).await.unwrap();
    println!("Sent start pump cmd");
    Ok(StatusCode::OK)
}

fn with_sender(sender: Sender<PumpStartCommand>) -> impl Filter<Extract = (Sender<PumpStartCommand>,), Error = Infallible> + Clone {
    warp::any().map(move || sender.clone())
}

pub async fn serve(
    sender: Sender<PumpStartCommand>,
) {

    let motor_routes = warp::path!("motors" / u32 / u32)
        .and(warp::post())
        .and(with_sender(sender.clone()))
        .and_then(motor_handler);

    let health_route = warp::path!("health")
        .map(|| StatusCode::OK);

    let routes = health_route.or(motor_routes);
    warp::serve(routes)
        .run(([0, 0, 0, 0], 3030))
        .await;
}
