{mkSecret, network, ...}: {
  sops.secrets.mosquitto-password = mkSecret "mosquitto-password" {};

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = network.routerIp;
        users = {
          "rw" = {
            acl = ["readwrite #"];
            passwordFile = "/run/secrets/mosquitto-password";
          };
        };
      }
      {
        address = "127.0.0.1";
        users = {
          "rw" = {
            acl = ["readwrite #"];
          };
        };
      }
    ];
  };

  networking.firewall.allowedTCPPorts = [1883];
  networking.firewall.allowedUDPPorts = [1883];
}
