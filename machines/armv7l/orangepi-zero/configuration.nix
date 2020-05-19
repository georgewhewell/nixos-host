{ config, pkgs, lib, ... }:

{

  networking.hostName = "orangepi-zero";

  hardware.firmware = with pkgs; lib.mkForce [ armbian-firmware ];

  boot.initrd.availableKernelModules = [ "sunxi" "wire" "nfs" ];

  boot.kernelParams = [ "boot.shell_on_fail" "console=ttyS0,115200" "earlycon=uart,mmio32,0x1c28000" "transparent_hugepage=never" ];
  console.extraTTYs = [ "ttyS0" ];

  networking.useDHCP = true;

  usb-gadget = {
    enable = true;
    initrdDHCP = true;
  };

  imports = [
    ../common.nix
  ];

  system.build.dtbName = "sun8i-h2-plus-orangepi-zero.dtb";
  system.build.ubootDefconfig = "orangepi_zero_defconfig";

}
