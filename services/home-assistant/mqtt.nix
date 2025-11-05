{...}: {
  deployment.keys."mosquitto-password" = {
    keyCommand = ["pass" "mqtt/home-assistant"];
    destDir = "/run/secrets";
    user = "mosquitto";
    group = "mosquitto";
    permissions = "0400";
  };

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "192.168.23.1";
        users = {
          "rw" = {
            acl = ["readwrite #"];
            passwordFile = "/run/secrets/mosquitto-password";
          };
        };
      }
    ];
  };

  networking.firewall.allowedTCPPorts = [1883];
  networking.firewall.allowedUDPPorts = [1883];
}
