#!/usr/bin/env python3
"""Apply and verify a PPT cap on every expected AMD reference V620."""

import argparse
from pathlib import Path
import sys
import time


IDENTITY = {
    "vendor": "0x1002",
    "device": "0x73a1",
    "subsystem_vendor": "0x1002",
    "subsystem_device": "0x0e34",
}


def apply_caps(devices: Path, watts: int, expected_count: int) -> list[str]:
    """Cap every matching card, returning errors instead of accepting a subset."""
    target = watts * 1_000_000  # hwmon uses microwatts, unlike the SMU.
    errors = []
    found = 0
    for device in sorted(devices.glob("*")):
        try:
            if any((device / key).read_text().strip() != value
                   for key, value in IDENTITY.items()):
                continue
        except OSError:
            continue
        found += 1
        try:
            sensors = [sensor for sensor in (device / "hwmon").glob("hwmon*")
                       if (sensor / "name").read_text().strip() == "amdgpu"]
            if len(sensors) != 1:
                raise ValueError(f"expected one amdgpu hwmon, found {len(sensors)}")
            sensor = sensors[0]
            minimum = int((sensor / "power1_cap_min").read_text())
            maximum = int((sensor / "power1_cap_max").read_text())
            if not minimum <= target <= maximum:
                raise ValueError(
                    f"{watts} W outside reported range "
                    f"{minimum / 1_000_000:g}–{maximum / 1_000_000:g} W; "
                    "boot the patched kernel if the minimum is still 250 W"
                )
            cap = sensor / "power1_cap"
            if int(cap.read_text()) != target:
                cap.write_text(f"{target}\n")
                actual = int(cap.read_text())
                if actual != target:
                    raise ValueError(f"cap readback is {actual}, expected {target} µW")
                print(f"{device.name}: verified {watts} W PPT cap", flush=True)
        except (OSError, ValueError) as error:
            errors.append(f"{device.name}: {error}")
    if found != expected_count:
        errors.append(f"expected {expected_count} reference V620s, found {found}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--watts", type=int, required=True)
    parser.add_argument("--expected-count", type=int, required=True)
    args = parser.parse_args()
    if not 120 <= args.watts <= 250 or args.expected_count < 1:
        parser.error("watts must be 120–250 and expected-count must be positive")
    # PCI enumeration and amdgpu hwmon registration may finish after systemd
    # starts us. Keep the cards already discovered capped while waiting.
    deadline = time.monotonic() + 60
    while True:
        errors = apply_caps(Path("/sys/bus/pci/devices"), args.watts, args.expected_count)
        if not errors:
            return 0
        if time.monotonic() >= deadline:
            print("\n".join(errors), file=sys.stderr)
            return 1
        time.sleep(2)


if __name__ == "__main__":
    sys.exit(main())
