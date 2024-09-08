{ lib, ... }:

let
  setting = "600@1000";
  devices = [
    "SteelSeries SteelSeries Aerox 3 Wireless"
    "Logitech G Pro Gaming Mouse"
    "Logitech G305"
    "Logitech USB Receiver"
    "Glorious Model O"
    "Logitech, Inc. USB Receiver"
  ];
in
{
  services.udev.extraHwdb = lib.concatMapStrings
    (n: "\nmouse:usb:*:name:${n}:*\n MOUSE_DPI=${setting}\n")
    (devices);
}
