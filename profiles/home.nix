{ config, pkgs, ... }:

{
  # Config for machines on home network
  time.timeZone = "Europe/London";

  services.avahi = {
    enable = true;
    nssmdns = true;
    publish.enable = true;
    publish.addresses = true;
  };

}
