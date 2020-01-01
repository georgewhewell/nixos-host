{ config, pkgs, ...}:

{

  # BT audio passthu
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  users.users.pulse.extraGroups = [ "lp" ];

  hardware.pulseaudio = {
    enable = true;
    extraModules = [ pkgs.pulseaudio-modules-bt ];
    support32Bit = true;
    systemWide = true;
    extraConfig = ''
      # make bluetooth work?
      load-module module-bluetooth-policy
      load-module module-bluetooth-discover
    '';
  };

  systemd.services.spotifyd = {
    description = "spotifyd client";
    after = [ "network.target" ];
    wantedBy = ["multi-user.target"];
    serviceConfig.ExecStart = ''
      ${pkgs.spotifyd}/bin/spotifyd --username 1139118329 --password Oojae0ash2sh --device-name "UE Mobile Boombox"
    '';
  };

  blind-engine.enable = true;

  # deCONZ
  environment.systemPackages = with pkgs; [
    deCONZ.deCONZ
  ];

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
      ExecStart = "${pkgs.deCONZ.deCONZ}/bin/deCONZ -platform minimal";
      ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      Restart = "always";
      RestartSec = "10s";
      StartLimitInterval = "1min";
      User = "deconz";
    };
  };

  users.extraUsers."hass".extraGroups = [ "dialout" ];

  services.home-assistant = {
    enable = true;
    openFirewall = true;
    # configWritable = true;
    
    config = {
      homeassistant = {
        name = "Home";
	latitude = "2.87336";
	longitude = "117.22743";
	elevation = "100";
	unit_system = "metric";
	time_zone = "America/Los_Angeles";
      };
      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
        base_url = "https://home.satanic.link";
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" ];
      };
      frontend = {};
      history = {};
      config = {};
      deconz = {
        host = "127.0.0.1";
        port = "8080";
      };
      media_player = [
        {
          platform = "spotify";
          client_id = "5b3bb394c98643ff87d7bf60652b7dd2";
          client_secret = "6bf4008fadc34c50aefb5c179e9593c6";
          aliases = {

          };
        }
      ];
      };
  };

  services.nginx.virtualHosts."home.satanic.link" = {
     forceSSL = true;
     enableACME = true;
     locations."/" = {
       proxyPass = "http://127.0.0.1:8123";
       extraConfig = ''
         proxy_http_version 1.1;
         proxy_redirect http:// https://;
         proxy_set_header Host $host;
         proxy_set_header Upgrade $http_upgrade;
         proxy_set_header Connection "Upgrade";
         proxy_set_header X-Real-IP $remote_addr;
         proxy_buffering off;
       '';
     };
  };

}
