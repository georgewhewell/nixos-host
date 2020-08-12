
use {
    std::thread,
    std::time::Duration,
};


const ADDRESS : u16 = 0x4;
const BUS: &'static str = "/dev/i2c-0";
const PIN: u8 = 0;

use i2cdev::core::*;
use i2cdev::linux::{LinuxI2CDevice};

pub fn read_voltage() -> u32 {
    let mut dev = LinuxI2CDevice::new(&BUS, ADDRESS).unwrap();
    println!("Opened successfully");
    dev.smbus_write_i2c_block_data(0, &[5, PIN, 0, 0]).unwrap();
    thread::sleep(Duration::from_millis(100));
    println!("Set PIN to INPUIT, performing read");
    dev.smbus_write_i2c_block_data(0, &[3, PIN, 0, 0]).unwrap();
    thread::sleep(Duration::from_millis(100));
    println!("Reading response.. ");

    dev.smbus_read_byte().unwrap();
    thread::sleep(Duration::from_millis(100));
    println!("Goy response.. ");
    let res = dev.smbus_read_i2c_block_data(0, 4).unwrap();

    let result = res[1] as u32 * 256 + res[2] as u32;
    println!("Result: {:?}", result);

    result
}
