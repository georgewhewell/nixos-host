{ config, pkgs, lib, ... }:

{
  networking.hostName = "orangepi-zero";

  hardware.firmware = with pkgs; [ armbian-firmware ];

  boot.initrd.availableKernelModules = [ "sunxi" "wire" ];

  console.extraTTYs = [ "ttyS0" ];

  usb-gadget = {
    enable = true;
    initrdDHCP = true;
  };

  imports = [
    ../common.nix
  ];
}
