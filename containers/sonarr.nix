{ config, lib, pkgs, boot, networking, containers, ... }:

{
  systemd.services."container@sonarr" = {
    bindsTo = [ "mnt-Home.mount" "mnt-Media.mount" ];
    after = [ "mnt-Home.mount" "mnt-Media.mount" ];
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
