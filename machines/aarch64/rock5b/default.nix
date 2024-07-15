{ config, pkgs, lib, inputs, modulesPath, ... }:

{

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/nas-mounts.nix
    ../../../services/buildfarm-slave.nix
    # inputs.rock5b.nixosModules.apply-overlay
    # "${modulesPath}/installer/sd-card/sd-image-aarch64-installer.nix"
    # inputs.rock5b.nixosModules.kernel
  ];

  sconfig = {
    profile = "server";
    home-manager.enable = false;
    home-manager.enableGraphical = false;
  };

  # deployment.targetHost = "rock-5b.satanic.link";
  deployment.targetHost = "192.168.23.11";

  boot.supportedFilesystems = [ "vfat" "ext4" "zfs" ];
  systemd.services.zfs-mount.enable = false;

  fileSystems."/boot" =
    {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
      options = [ "iocharset=iso8859-1" "fmask=0022" "dmask=0022" ];
    };

  fileSystems."/" =
    {
      device = "zpool/root/rock5b";
      fsType = "zfs";
      # options = [ ];
    };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

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
    memoryPercent = 30;
    memoryMax = 1024 * 1024 * 1024;
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

  # fileSystems = lib.mkForce {
  #   "/" = { label = "NIXOS_ROOTFS"; };
  # };
  # Builds an (opinionated) rootfs image.
  # NOTE: *only* the rootfs.
  #       it is expected the end-user will assemble the image as they need.
  # boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" ];
  boot.kernelParams = [ "console=ttyS2,1500000n8" ];
  # environment.systemPackages = [  ];

  # system.build.rootfsImage =
  #   pkgs.callPackage
  #     (
  #       { callPackage
  #       , lib
  #       , populateCommands
  #       ,
  #       }:
  #       callPackage "${pkgs.path}/nixos/lib/make-ext4-fs.nix" ({
  #         inherit (config.sdImage) storePaths;
  #         compressImage = false;
  #         populateImageCommands = populateCommands;
  #         volumeLabel = config.fileSystems."/".label;
  #       }
  #       // lib.optionalAttrs (config.sdImage.rootPartitionUUID != null) {
  #         uuid = config.sdImage.rootPartitionUUID;
  #       })
  #     )
  #     {
  #       populateCommands = ''
  #         mkdir -p ./files/boot
  #         ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
  #       '';
  #     };

  # interfaces should exist before stage2
  boot.initrd.kernelModules = [
    # "r8125"
    "nvme"
    "r8169"
    # "iwlwifi"
    # "bcachefs"
    # "xhci_pci"
    # "ehci_pci"
    # "ahci"
    # "usb_storage"
  ];

  system.stateVersion = "24.03";

  # nixpkgs.overlays = [
  #   (self: _: {
  #     linuxPackages_latest = self.linuxPackagesFor (self.linux_latest.override (o: {
  #       argsOverride = old: {
  #         kernelPatches = old.kernelPatches ++ [{ patch = ./faster-pd.patch; }];
  #       };
  #     }));
  #   })
  # ];

  boot.kernelPatches = [
    { patch = ./save-bar-space.patch; }
    { patch = ./rk3588-pci.patch; }
  ];

  services.iperf3.enable = true;

  # boot.kernel.sysctl = {
  #   "net.ipv4.conf.all.arp_filter" = true;
  #   "net.ipv4.conf.all.forwarding" = false;
  #   "net.ipv6.conf.all.forwarding" = false;
  # };

  networking = {
    hostName = "rock-5b";
    nameservers = [ "192.168.23.5" ];
    useNetworkd = true;
    useDHCP = false;
    nat.enable = false;
    firewall.enable = false;

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
          # BindCarrier = "enP4p65s0";
          ConfigureWithoutCarrier = false;
          IPv6AcceptRA = true;
        };
        address = [
          "192.168.23.11/24"
        ];
        routes = [
          {
            Gateway = "192.168.23.1";
            # Table = 1000;
            Metric = 1;
          }
        ];
        # routingPolicyRules = [
        #   {
        #     routingPolicyRuleConfig = {
        #       From = "192.168.23.11";
        #       Table = 1000;
        #     };
        #   }
        # ];
        linkConfig = {
          RequiredForOnline = false;
          # CarrierLossPolicy = "drop";
          # ActivationPolicy = "always-up";
          # ActivationPolicy = "link";
          # ActivationPolicy = "bound";
        };
      };
      "30-wifi" = {
        matchConfig.Driver = "iwlwifi";
        address = [
          "192.168.23.250/24"
        ];
        routes = [
          {
            Gateway = "192.168.23.1";
            # Table = 1001;
            Metric = 10;
          }
        ];
        # routingPolicyRules = [
        #   {
        #     routingPolicyRuleConfig = {
        #       From = "192.168.23.250";
        #       Table = 1001;
        #     };
        #   }
        # ];
        networkConfig = {
          # BindCarrier = "wlan0";
          ConfigureWithoutCarrier = false;
          IPv6AcceptRA = true;
        };
        linkConfig = {
          RequiredForOnline = false;
          # CarrierLossPolicy = "drop";
          # BindCarrier = true;
          # ActivationPolicy = "link";
        };
      };
    };
  };

  # services.dnsmasq = {
  #   enable = true;
  #   alwaysKeepRunning = true;
  #   settings = {
  #     interface = "enu1u1";
  #     dhcp-range = "192.168.22.2,192.168.22.254,24h";
  #   };
  #   extraConfig = ''
  #     bind-interfaces
  #   '';
  # };

  environment.systemPackages = with pkgs; [
    iperf
    bcachefs-tools
    lshw
    pciutils
    usbutils
  ];

  # require interface to be up before starting dnsmasq
  # systemd.services.dnsmasq.after = [ "sys-subsystem-net-devices-enu1u1.device" ];

  services.irqbalance.enable = lib.mkDefault true;
  hardware.wirelessRegulatoryDatabase = true;

  powerManagement.enable = false;
  # powerManagement.cpuFreqGovernor = lib.mkDefault " ondemand ";

  services.openssh.enable = true;
  services.openssh.permitRootLogin = "yes";

}
