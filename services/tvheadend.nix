{ options, config, lib, pkgs, ... }:

{

  boot.kernelPatches = [
    {
      # Disable regular kernel em28xx module since dependencies will
      # collide with other v4l2 from tbs modules
      name = "disable em28xx";
      patch = null;
      extraConfig = ''
        VIDEO_EM28XX n
      '';
    }
  ];

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_4_19;
  boot.extraModulePackages = [
    pkgs.linuxPackages_4_19.tbs
  ];

  environment.systemPackages = with pkgs; [ dtv-scan-tables ];
  hardware.firmware = [ pkgs.libreelec-dvb-firmware ];
  services.tvheadend.enable = true; 
  networking.firewall.allowedTCPPorts = [ 9981 9982 ];

}
