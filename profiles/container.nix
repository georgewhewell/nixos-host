{ config, lib, pkgs, ... }:

{
  imports = [ ./common.nix ];

  boot.isContainer = true;
  time.timeZone = "Europe/London";
  environment.noXlibs = true;

  i18n.supportedLocales = [ (config.i18n.defaultLocale + "/UTF-8") ];

  services.xserver.enable = false;
  sound.enable = false;

  networking = {
    enableIPv6 = false;
    interfaces.eth0 = {
      useDHCP = true;
    };
  };
}
