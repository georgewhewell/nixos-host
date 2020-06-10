{ config, lib, pkgs, ... }:
let password = builtins.readFile "/var/lib/iodined.password"; in
{
  services.iodine.server = {
    enable = true;
    ip = "172.16.10.1/24";
    domain = "t.tsar.su";
    extraConfig = "-P ${password}";
  };

  networking.firewall.allowedUDPPorts = [ 53 ];
}
