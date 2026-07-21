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

  # LAN, WiFi VLAN, and wireguard clients only — never the WAN interface.
  # (mosquitto only binds routerIp/localhost, but don't rely on that alone.)
  networking.firewall.interfaces."br0.lan".allowedTCPPorts = [1883];
  networking.firewall.interfaces."br0.lan.50".allowedTCPPorts = [1883];
  networking.firewall.interfaces."wg-home".allowedTCPPorts = [1883];
}
