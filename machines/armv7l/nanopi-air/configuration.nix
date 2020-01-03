{ config, pkgs, lib, ... }:

{
  networking.hostName = "nanopi-air";

  usb-gadget = {
    enable = true;
    initrdDHCP = true;
  };

  hardware.firmware = with pkgs; [ armbian-firmware ];

  imports = [
    ../common.nix
  ];
}
