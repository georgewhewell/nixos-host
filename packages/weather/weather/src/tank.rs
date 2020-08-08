use vl53l0x::VL53L0x;
use linux_embedded_hal::{I2cdev};
use serde::Serialize;
use shared_bus;

#[derive(Serialize)]
pub struct TankState {
    mm: u16,
}

pub fn read_tank_level() -> TankState {
    println!("Reading tank level!");
    let i2c_bus = I2cdev::new("/dev/i2c-0").unwrap();
    let manager = shared_bus::BusManager::<std::sync::Mutex<_>, _>::new(i2c_bus);

    let mut tof = VL53L0x::new(manager.acquire()).unwrap();
    match tof.read_range_mm() {
        Ok(meas) => {
            println!("vl: millis {}\r\n", meas);
            TankState {
                mm: meas,
            }
        }
        Err(e) => {
            println!("Err meas: {:?}\r\n", e);
            TankState {
                mm: 0,
            }
        }
    }

}