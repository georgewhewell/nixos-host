{ config, pkgs, ... }:

{

  services.mosquitto = {
    enable = true;
    host = "0.0.0.0";
    checkPasswords = true;
    allowAnonymous = false;
    users = {
      "rw" = {
        acl = [ "topic readwrite #" ];
        password = pkgs.secrets.mqtt-password;
      };
    };
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
