import sys
import time
import math
import struct

import smbus2 as smbus

address = 0x04
bus = smbus.SMBus(0)

uRead_cmd = [7]
unused = 0


def write_i2c_block(address, block):
    try:
        return bus.write_i2c_block_data(address, 1, block)
    except IOError as exc:
        print(f'Failed to write i2c block: {exc}')
        return [-1]

def read_i2c_block(address):
    try:
        return bus.read_i2c_block_data(address, 1, 4)
    except IOError as exc:
        print(f'Failed to read i2c block: {exc}')
    return [-1]


# Read value from Ultrasonic
def ultrasonicRead(pin):
    write_i2c_block(address, uRead_cmd + [pin, unused, unused])
    time.sleep(.2)
    number = read_i2c_block(address)
    print(f"resp: {number}")
    return (number[1] * 256 + number[2])


def get_distance():
    return ultrasonicRead(4)
