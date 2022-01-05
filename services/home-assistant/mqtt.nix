{ config, pkgs, ... }:

{

  services.mosquitto = {
    enable = true;
    listeners = [{
      address = "0.0.0.0";
    users = {
      "rw" = {
        acl = [ "readwrite #" ];
        password = pkgs.secrets.mqtt-password;
      };
    };
    }];
  };

  services.home-assistant.config = {
    mqtt = {
      broker = "127.0.0.1";
      username = "rw";
      password = pkgs.secrets.mqtt-password;
      discovery = true;
    };
  };

  networking.firewall.allowedTCPPorts = [ 1883 8081 ];
  networking.firewall.allowedUDPPorts = [ 1883 ];

}
