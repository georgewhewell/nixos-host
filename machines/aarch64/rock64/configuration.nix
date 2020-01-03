{ config, pkgs, lib, ... }:

{
  networking.hostName = "rock64";

  boot.kernelParams = [
    "earlycon=uart8250,mmio32,0xff130000"
    "coherent_pool=1M"
  ];

  services.mingetty.serialSpeed = [ 1500000 ];

  # Ideally this would be run before the interface is brought up, but
  # that doesn't seem to be supported by the driver.
  networking.localCommands = ''
    ${pkgs.ethtool}/bin/ethtool -K eth0 rx off tx off
  '';

  imports = [
    ../common.nix
  ];

}
