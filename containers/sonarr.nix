{ config, lib, pkgs, boot, networking, containers, ... }:

{

  systemd.services."container@sonarr" = {
    bindsTo = [ "mnt-Home.mount" "mnt-Media.mount" ];
    after = [ "mnt-Home.mount" "mnt-Media.mount" ];
  };

  services.nginx = {
    virtualHosts."sonarr.satanic.link" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        extraConfig = ''
          resolver 192.168.23.5;
          proxy_buffering off;
        '';
        proxyPass = "http://sonarr.lan:8989";
        proxyWebsockets = true;
      };
    };
  };

  containers.sonarr = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0.lan";

    bindMounts = {
      "/var/lib/sonarr" = {
        hostPath = "/var/lib/sonarr";
        isReadOnly = false;
      };
      "/mnt/Media" = {
        hostPath = "/mnt/Media";
        isReadOnly = false;
      };
    };

    config = {
      imports = [ ../profiles/container.nix ];

      networking.hostName = "sonarr";
      services.sonarr = {
        enable = true;
        openFirewall = true;
      };

    };
  };
}
