{ config, pkgs, lib, ... }:

{

  networking.hostName = "licheepi-zero";

  hardware.firmware = with pkgs; [ armbian-firmware ];

  boot.initrd.availableKernelModules = [ "sunxi" "wire" ];

  boot.kernelParams = [ "boot.shell_on_fail" "console=ttyS0,115200" "earlycon=uart,mmio32,0x1c28000" "transparent_hugepage=never" ];
  console.extraTTYs = [ "ttyS0" ];

  networking.useDHCP = true;

  imports = [
    ../common.nix
  ];

  system.build.dtbName = "sun8i-v3s-licheepi-zero.dtb";
  system.build.ubootDefconfig = "licheepi_zero_defconfig";

}
