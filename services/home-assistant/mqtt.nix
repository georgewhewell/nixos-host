{mkSecret, network, ...}: {
  sops.secrets.mosquitto-password = mkSecret "mosquitto-password" {};

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        # MQTT belongs to the service plane, not the routing address. During
        # the VPP handoff .1 moves to the DPU while this broker remains on the
        # old router at .31.
        address = network.controlPlaneIp;
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
  # (mosquitto only binds controlPlaneIp/localhost, but don't rely on that alone.)
  networking.firewall.interfaces."br0.lan".allowedTCPPorts = [1883];
  networking.firewall.interfaces."br0.lan.50".allowedTCPPorts = [1883];
  networking.firewall.interfaces."wg-home".allowedTCPPorts = [1883];
}
