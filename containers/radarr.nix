{ config, lib, pkgs, boot, networking, containers, ... }:

{
  systemd.services."container@radarr" = {
    bindsTo = [ "mnt-Home.mount" "mnt-Media.mount" ];
    after = [ "mnt-Home.mount" "mnt-Media.mount" ];
  };

  containers.radarr = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0.lan";

    bindMounts = {
      "/var/lib/radarr" = {
        hostPath = "/var/lib/radarr";
        isReadOnly = false;
      };
      "/mnt/Media" = {
        hostPath = "/mnt/Media";
        isReadOnly = false;
      };
    };

    config = {
      imports = [ ../profiles/container.nix ];

      networking.hostName = "radarr";

      services.radarr = {
        enable = true;
        openFirewall = true;
      };

    };

  };
}
