{ config, pkgs, lib, ... }:

{
  networking.hostName = "amlogic-s912";


  hardware.firmware = with pkgs; [ meson-firmware armbian-firmware ];

  # make /dev/dri0 be panfrost?
  boot.initrd.availableKernelModules = [ "panfrost" ];
  networking.firewall.allowedTCPPorts = [ 8080 ];

  boot.kernelPackages = pkgs.linuxPackages_head;
  boot.kernelPatches = [
      {
        name = "enable staging";
        patch = null;
        extraConfig = ''
          STAGING_MEDIA y
        '';
      }
      {
        name = "integ patches";
        patch = pkgs.fetchurl {
          name = "thepatch";
          url = ''https://github.com/torvalds/linux/compare/v5.7-rc1...chewitt:amlogic-5.7-integ.patch'';
          sha256 = "17ghb4ii055iyfag7ka6zclh5g9gnbgnrahakbpas5zdviy65s8w";
        };
      }
  ];

  users.users.grw.extraGroups = [ "input" "pulse" ];

  sound.enable = true;

  # dont need this- interferes with kodi
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;
  
  security.polkit.enable = true;
  services.upower.enable = true;

  boot.plymouth.enable = false;

  systemd.services.kodi-gbm = {
    environment = {
      WINDOWING = "gbm";
    };
    wants = [ "network-online.target" "polkit.service" ];
    conflicts = [ "getty@tty1.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.kodi-gbm}/bin/kodi-standalone";
      StandardInput = "tty";
      StandardOutput = "tty";
      TTYPath = "/dev/tty1";
      PAMName = "login";
      User = "grw";
    };
  };

  hardware.opengl = {
    enable = true;
    s3tcSupport = true;
    extraPackages = with pkgs; [ libva libvdpau-va-gl ];
  };

  environment.systemPackages = with pkgs; [
    libva-utils
    v4l-utils
  ];

  imports = [
    ../common.nix
    ../../../profiles/nas-mounts.nix
  ];
}
