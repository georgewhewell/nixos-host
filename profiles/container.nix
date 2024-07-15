{ config, lib, pkgs, ... }:

{
  imports = [ ./common.nix ];

  boot.isContainer = true;
  time.timeZone = "Europe/London";
  #  environment.noXlibs = true;
  services.fwupd.enable = lib.mkForce false;

  i18n.supportedLocales = [ (config.i18n.defaultLocale + "/UTF-8") ];

  sound.enable = false;
  services = {
    irqbalance.enable = lib.mkForce false;
  };

  networking = {
    interfaces.eth0 = {
      useDHCP = true;
    };
    useHostResolvConf = false;
    nameservers = [ "192.168.23.5" ];
  };
}
