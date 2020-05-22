{ config, pkgs, lib, ... }:

{
  networking.hostName = "amlogic-s912";

  hardware.firmware = with pkgs; [ meson-firmware armbian-firmware ];

  # make /dev/dri0 be panfrost?
  boot.initrd.availableKernelModules = [ "panfrost" ];
  networking.firewall.allowedTCPPorts = [ 8080 ];

  boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor (pkgs.linux_testing.override {
    argsOverride = rec {
      src = pkgs.fetchFromGitHub {
        owner = "150balbes";
        repo = "Amlogic_s905-kernel";
        rev = "5dc4b922d617a74d0ee3acc6c1649c5e4a1ea956";
        sha256 = "0m08v5b36f541546604nyxvi8rq7n98hbbg9iz7zcz8284c2j7vi";
      };
      version = "5.7-rc6";
      modDirVersion = "5.7.0-rc6";
    };
  }));

  boot.kernelPatches = [
      {
        name = "enable staging";
        patch = null;
        extraConfig = ''
          STAGING_MEDIA y
        '';
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
      ExecStart = "${pkgs.hello}/bin/kodi-standalone";
      StandardInput = "tty";
      StandardOutput = "tty";
      TTYPath = "/dev/tty1";
      PAMName = "login";
      User = "grw";
    };
  };

  hardware.opengl = {
    enable = true;
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
