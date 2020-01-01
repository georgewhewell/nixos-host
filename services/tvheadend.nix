{ options, config, lib, pkgs, ... }:

{

  /*
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_4_19;
  boot.extraModulePackages = [
    config.boot.kernelPackages.tbs
    ];
  */
  environment.systemPackages = with pkgs; [ dtv-scan-tables ];
  hardware.firmware = [ pkgs.libreelec-dvb-firmware ];
  services.tvheadend.enable = true; 
  networking.firewall.allowedTCPPorts = [ 9981 9982 ];

}
