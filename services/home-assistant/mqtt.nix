{...}: {
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "192.168.23.14";
        users = {
          "rw" = {
            acl = ["readwrite #"];
            password = "i503Myc3b6wOYKM8fDwypUstI";
          };
        };
      }
    ];
  };

  networking.firewall.allowedTCPPorts = [1883];
  networking.firewall.allowedUDPPorts = [1883];
}
