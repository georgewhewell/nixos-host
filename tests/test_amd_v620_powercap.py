"""Exercise device selection and fail-closed cap verification using fake sysfs."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "powercap", Path(__file__).parents[1] / "profiles/amd-v620-powercap.py"
)
powercap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(powercap)


class PowerCapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.devices = Path(self.temp.name)

    def card(self, bdf, **identity):
        device = self.devices / bdf
        device.mkdir()
        for key, value in (powercap.IDENTITY | identity).items():
            (device / key).write_text(value + "\n")
        hwmon = device / "hwmon/hwmon9"
        hwmon.mkdir(parents=True)
        for name, value in {
            "name": "amdgpu", "power1_cap_min": "120000000",
            "power1_cap_max": "250000000", "power1_cap": "250000000",
        }.items():
            (hwmon / name).write_text(value + "\n")
        return hwmon

    def test_caps_all_four_renumbered_cards_and_leaves_other_boards_untouched(self):
        cards = [self.card(f"0000:{bus}:00.0") for bus in ("17", "3a", "4f", "62")]
        others = [
            self.card("0000:70:00.0", device="0x1586"),  # Halo iGPU
            self.card("0000:71:00.0", subsystem_device="0x9999"),
            self.card("0000:72:00.0", subsystem_vendor="0x9999"),
            self.card("0000:73:00.0", vendor="0x1234"),
        ]
        self.assertEqual(powercap.apply_caps(self.devices, 180, 4), [])
        for sensor in cards:
            self.assertEqual((sensor / "power1_cap").read_text(), "180000000\n")
        for sensor in others:
            self.assertEqual((sensor / "power1_cap").read_text(), "250000000\n")
        # Periodic verification must not rewrite an already-correct cap.
        with patch.object(Path, "write_text", side_effect=AssertionError("unexpected write")):
            self.assertEqual(powercap.apply_caps(self.devices, 180, 4), [])

    def test_a_successful_card_does_not_hide_missing_or_unready_cards(self):
        good = self.card("0000:17:00.0")
        unready = self.card("0000:3a:00.0")
        (unready / "power1_cap").unlink()
        errors = powercap.apply_caps(self.devices, 180, 4)
        self.assertEqual(len(errors), 2)
        self.assertIn("0000:3a:00.0", errors[0])
        self.assertIn("expected 4 reference V620s, found 2", errors[1])
        self.assertEqual((good / "power1_cap").read_text(), "180000000\n")
        (unready / "power1_cap").write_text("250000000\n")
        self.card("0000:4f:00.0")
        self.card("0000:62:00.0")
        self.assertEqual(powercap.apply_caps(self.devices, 180, 4), [])

    def test_unpatched_kernel_is_rejected_without_writing(self):
        sensor = self.card("0000:17:00.0")
        (sensor / "power1_cap_min").write_text("250000000\n")
        errors = powercap.apply_caps(self.devices, 180, 1)
        self.assertIn("boot the patched kernel", errors[0])
        self.assertEqual((sensor / "power1_cap").read_text(), "250000000\n")

    def test_write_must_read_back_the_requested_cap(self):
        self.card("0000:17:00.0")
        with patch.object(Path, "write_text", return_value=10):
            errors = powercap.apply_caps(self.devices, 180, 1)
        self.assertIn("cap readback is 250000000, expected 180000000", errors[0])

    def test_no_devices_is_a_failure(self):
        self.assertEqual(powercap.apply_caps(self.devices, 180, 4),
                         ["expected 4 reference V620s, found 0"])


if __name__ == "__main__":
    unittest.main()
