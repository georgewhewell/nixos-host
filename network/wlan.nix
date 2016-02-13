{ config, lib, pkgs, ... }:

{
  # Wifi needs this because Broadcomm
  nixpkgs.config.allowUnfree = true;

  # Enables wireless support via wpa_supplicant.
  networking.wireless.enable = true;
  networking.firewall.enable = false;

  # wl driver
  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];

  # enable MASQUERADE
  /*networking.localCommands = ''
    /run/current-system/sw/bin/iptables -t nat -A POSTROUTING -o wlp4s0 -j MASQUERADE
  '';*/
}
