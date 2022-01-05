{ config, pkgs, ... }:

{
  services.udev.extraRules = ''
    SUBSYSTEM==“tty”, ATTRS{idVendor}==“0658”, ATTRS{idProduct}==“0200”, SYMLINK+=“zwave”
  '';

  users.users."deconz" = {
    createHome = true;
    isNormalUser = true;
    group = "dialout";
    home = "/home/deconz";
  };

  systemd.services.deconz = {
    enable = true;
    description = "deconz";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    stopIfChanged = false;
    serviceConfig = {
      ExecStart = "${pkgs.deCONZ.deCONZ}/bin/deCONZ -platform minimal --ws-port=8081";
      ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      Restart = "always";
      RestartSec = "10s";
      StartLimitIntervalSec = 60;
      User = "deconz";
    };
  };
}
