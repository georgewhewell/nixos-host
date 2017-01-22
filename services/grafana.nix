{ config, lib, pkgs, ... }:

{
  services.grafana = {
   enable = true;
   addr = "0.0.0.0";
   security = {
     adminUser = "admin";
     adminPassword = "password";
   };
  };

  networking.firewall.allowedTCPPorts = [ 3000 ];

}
