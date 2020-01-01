import argparse
import pytz

from datetime import datetime
from astral import Astral
from bluepy.btle import Peripheral

OPEN   = b"\x00\xff\x00\x00\x9a\x0d\x01\x00\x96"
CLOSE  = b"\x00\xff\x00\x00\x9a\x0d\x01\x64\xf2"

parser = argparse.ArgumentParser()
parser.add_argument('mac_address', action='store', help='MAC address of BLE peripheral')
parser.add_argument('--astral', action='store_true')
parser.add_argument('--close', action='store_true')

def main():
    args = parser.parse_args()
    print('Connecting to ' + args.mac_address)

    blind = Peripheral(args.mac_address)
    print('Connected...')

    if args.astral:
        a = Astral()
        city = a['London']
        now = datetime.now(pytz.utc)
        sun = city.sun(date=now, local=True)
        if sun['sunrise'] <= now <= sun['sunset']:
            blind.writeCharacteristic(0x000e, OPEN)
        else:
            blind.writeCharacteristic(0x000e, CLOSE)
        return

    if args.close:
        blind.writeCharacteristic(0x000e, CLOSE)
    else:
        blind.writeCharacteristic(0x000e, OPEN)

if __name__ == '__main__':
    main()
