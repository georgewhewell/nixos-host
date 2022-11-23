{ config, pkgs, lib, ... }: {

  home.packages = with pkgs; [
    wdisplays
  ];

  # services.gammastep = {
  #   enable = true;
  #   provider = "geoclue2";
  #   tray = true;
  #   settings.general = {
  #     brightness-day = 1.0;
  #     brightness-night = 0.4;
  #   };
  # };

  systemd.user.services = {
    geoclue-agent = {
      Unit = {
        Before = [ "gammastep.service" ];
        Description = "Geoclue agent";
      };
      Service = {
        Type = "exec";
        ExecStart = "${pkgs.geoclue2.override { withDemoAgent = true;}}/libexec/geoclue-2.0/demos/agent";
        Restart = "on-failure";
        PrivateTmp = true;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };


}
