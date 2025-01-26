{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/nas-mounts.nix
    ../../../services/buildfarm-slave.nix
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  sconfig = {
    profile = "server";
    home-manager.enable = true;
    home-manager.enableGraphical = false;
  };

  deployment.targetHost = "192.168.23.18";
  deployment.targetUser = "grw";

  boot.supportedFilesystems = ["vfat" "ext4" "zfs"];
  systemd.services.zfs-mount.enable = false;

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/9E7A-69DA";
    fsType = "vfat";
    options = ["iocharset=iso8859-1" "fmask=0022" "dmask=0022"];
  };

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
  };

  fileSystems."/" = {
    device = "zpool/root/nixos";
    fsType = "zfs";
    # options = [ ];
  };

  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = lib.mkForce true;
    };
  };

  zramSwap = {
    enable = true;
    priority = 10;
    algorithm = "lz4";
    swapDevices = 4;
    memoryPercent = 40;
    memoryMax = 2 * 1024 * 1024 * 1024;
  };

  systemd.extraConfig = ''
    RuntimeWatchdogSec=1m
    ShutdownWatchdogSec=1m
  '';

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.extraModprobeConfig = ''
    options iwlwifi swcrypto=0
    options iwlwifi power_save=0
    options iwlwifi uapsd_disable=1
    options iwlmvm power_scheme=1
    options cfg80211 ieee80211_regdom="CH"
  '';

  boot.kernelParams = ["console=ttyS2,1500000n8"];

  # interfaces should exist before stage2
  boot.initrd.kernelModules = [
    "nvme"
    "r8169"
  ];

  system.stateVersion = "24.03";

  services.iperf3.enable = true;

  networking = {
    hostName = "rock-5b";
    nameservers = ["192.168.23.254"];
    useNetworkd = true;

    useDHCP = false;
    nat.enable = false;
    firewall.enable = true;

    wireless.iwd = {
      enable = true;
      settings = {
        IPv6 = {
          Enabled = true;
        };
        Settings = {
          AutoConnect = true;
        };
      };
    };
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    networks = {
      "10-lan" = {
        matchConfig.Driver = "r8169";
        networkConfig = {
          IPv6AcceptRA = true;
        };
        address = [
          "192.168.23.18/24"
        ];
        routes = [
          {
            Gateway = "192.168.23.1";
            Metric = 1;
          }
        ];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    iperf
    bcachefs-tools
    lshw
    pciutils
    usbutils
  ];

  services.ollama.enable = true;

  services.irqbalance.enable = lib.mkDefault true;
  hardware.wirelessRegulatoryDatabase = true;

  powerManagement.enable = false;
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
}
