{ config, pkgs, lib, ... }:

{

  networking.hostName = "nanopi-air";
  hardware.firmware = with pkgs; lib.mkForce [ armbian-firmware ];

  system.build.dtbName = "sun8i-h3-nanopi-air.dtb";
  system.build.ubootDefconfig = "nanopi_neo_air_defconfig";

  boot.kernelParams = [ "boot.shell_on_fail" "console=ttyS0,115200" "earlycon=uart,mmio32,0x1c28000" "transparent_hugepage=never" ];
  console.extraTTYs = [ "ttyS0" ];

  powerManagement.cpuFreqGovernor = lib.mkForce "powersave";

  imports = [
    ../common.nix
    ../../../profiles/wireless.nix
  ];
}
