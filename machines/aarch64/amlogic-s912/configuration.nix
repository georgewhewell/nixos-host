{ config, pkgs, lib, ... }:

{
  networking.hostName = "amlogic-s912";

  security.polkit.enable = true;
  services.upower.enable = true;

  hardware.firmware = with pkgs; [ meson-firmware armbian-firmware ];

  # make /dev/dri0 be panfrost?
  boot.initrd.availableKernelModules = [ "panfrost" ];
  networking.firewall.allowedTCPPorts = [ 8080 ];

  boot.kernelPackages = 
    with pkgs; recurseIntoAttrs (linuxPackagesFor (
    buildLinux {
    version = "5.5-rc3";
    modDirVersion = "5.5.0-rc3";
    src = pkgs.fetchFromGitHub {
      owner = "chewitt";
      repo = "linux";
      rev = "amlogic-5.5-integ";
      sha256 = "0d6w7d0mv8lziyxm58wfx90rfp91kn8qg611mpqjmmwjhq2q2884";
    };

    inherit (pkgs) buildPackages stdenv;
    kernelPatches = pkgs.linux_testing.kernelPatches ++ [
      {
        name = "fix dts makefile";
        patch = ./dts.patch;
        extraConfig = ''
          STAGING_MEDIA y
        '';
      }
    ];
  }));

  users.users.grw.extraGroups = [ "input" "pulse" ];

  sound.enable = true;

  # dont need this- interferes with kodi
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  boot.plymouth.enable = false;

  services.xserver = {
    enable = true;
    videoDrivers = [ "modesetting" ];
    displayManager.sddm = {
      enable = true;
      autoLogin = {
        enable = true;
        user = "grw";
      };
    };
    desktopManager.kodi = {
      enable = true;
    };
    extraConfig = ''
      Section "OutputClass"
	Identifier "Meson"
	MatchDriver "meson"
	Driver "modesetting"
	Option "PrimaryGPU" "true"
      EndSection
    '';
  };
  /*
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
  */

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
