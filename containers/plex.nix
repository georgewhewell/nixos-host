{ config, lib, pkgs, boot, networking, containers, ... }:

{
  containers.plex = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";
    allowedDevices = [
      { modifier = "rw"; node = "/dev/dri/card0"; }
      { modifier = "rw"; node = "/dev/dri/renderD128"; }
    ];

    bindMounts = {
      "/dev/dri/card0" = {
        hostPath = "/dev/dri/card0";
        isReadOnly = false;
      };
      "/dev/dri/renderD128" = {
        hostPath = "/dev/dri/renderD128";
        isReadOnly = false;
      };
      "/var/lib/plex" = {
        hostPath = "/var/lib/plex";
        isReadOnly = false;
      };
      "/movies" = {
        hostPath = "/mnt/Media/Movies";
        isReadOnly = false;
      };
      "/tv" = {
        hostPath = "/mnt/Media/TV";
        isReadOnly = false;
      };
    };

    config = {
      imports = [ ../profiles/container.nix ];
      networking.hostName = "plex.lan";

      hardware.opengl = {
        enable = true;
        s3tcSupport = true;
        driSupport = true;
        driSupport32Bit = true;
        extraPackages = with pkgs; [
          vaapiVdpau
          (vaapiIntel.override { enableHybridCodec = true; })
          libvdpau-va-gl
          intel-media-driver
        ];
      };

      nixpkgs.config.allowUnfree = true;
      users.extraUsers.plex.extraGroups = [ "video" "render" ];
      environment.systemPackages = [ pkgs.libva-utils ];

      services.plex = {
        enable = true;
        openFirewall = true;
        dataDir = "/var/lib/plex";
      };
    };
  };
}
