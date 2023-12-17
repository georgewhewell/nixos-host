{ config, pkgs, lib, ... }:

{

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/intel-gfx.nix
    # ../../../profiles/tvbox-gbm.nix
    ../../../profiles/nas-mounts.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/thinkpad.nix
    ../../../services/docker.nix
  ];

  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableGraphical = false;
    };
  };

  # disable builtin screen
  boot = {
    # kernelParams = [ "video=eDP-1:d" ];
    kernelPackages = pkgs.linuxPackages_latest_lto_skylake;
    loader.timeout = 1;
    blacklistedKernelModules = [
      "mei"
      "mei_me"
      "mei_wdt"
      "acer_wmi"
      "applesmc"
      "intel_backlight"
    ];
  };

  fileSystems."/" =
    {
      device = "/dev/disk/by-label/root";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
    };

  # start kodi on boot
  # users.extraUsers.jellyfin.isNormalUser = true;
  # services.greetd = {
  #   enable = true;
  #   settings = rec {
  #     initial_session = {
  #       command = "${pkgs.kodi-gbm}/bin/kodi --standalone";
  #       user = "jellyfin";
  #     };
  #     default_session = initial_session;
  #   };
  # };

  services.undervolt = {
    enable = true;
    tempAc = 97;
    tempBat = 75;
    coreOffset = -115;
    gpuOffset = -60;
    uncoreOffset = -60;
    analogioOffset = -60;
  };

  networking.hostName = "yoga";

  networking.firewall.allowedTCPPorts = [ 9100 ];
  services.prometheus.exporters.node.openFirewall = lib.mkForce true;
}
