{ config, lib, pkgs, ... }:

{ 
  boot.isContainer = true;
  system.stateVersion = "18.03";
  time.timeZone = "Europe/London";
  environment.noXlibs = true;

  i18n.supportedLocales = [ (config.i18n.defaultLocale + "/UTF-8") ];

  documentation.enable = false;
  services.xserver.enable = false;
  sound.enable = false;

  networking = {
    enableIPv6 = false;
    interfaces.eth0 = {
      useDHCP = true;
    };
  };
}
