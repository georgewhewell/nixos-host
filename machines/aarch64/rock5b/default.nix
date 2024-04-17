{ config, pkgs, lib, inputs, ... }:

{

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/nas-mounts.nix
    ../../../services/buildfarm-slave.nix
    inputs.rock5b.nixosModules.apply-overlay
    inputs.rock5b.nixosModules.kernel
  ];

  sconfig = {
    profile = "server";
    home-manager.enable = true;
    home-manager.enableGraphical = false;
  };

  deployment.targetHost = "rock-5b.lan";

  fileSystems."/boot" =
    {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
      options = [ "iocharset=iso8859-1" ];
    };

  fileSystems."/" =
    {
      device = "/dev/nvme0n1p2";
      fsType = "ext4";
      options = [ "noatime" "discard" ];
    };

  boot = {
    loader = {
      efi = {
        efiSysMountPoint = "/boot";
        canTouchEfiVariables = true;
      };
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
      };
    };
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
    memoryPercent = 30;
    memoryMax = 1024 * 1024 * 1024;
  };

  # interfaces should exist before stage2
  boot.initrd.kernelModules = [
    "r8125"
    "r8169"
    "rt2800usb"
    "r8152"
  ];
  boot.initrd.availableKernelModules = [
    "usbhid"
    "md_mod"
    "raid0"
    "raid1"
    "raid10"
    "raid456"
    "ext2"
    "ext4"
    "sd_mod"
    "sr_mod"
    "mmc_block"
    "uhci_hcd"
    "ehci_hcd"
    "ehci_pci"
    "ohci_hcd"
    "ohci_pci"
    "xhci_hcd"
    "xhci_pci"
  ];
  system.stateVersion = "23.09";

  swapDevices = [ ];

  nixpkgs.overlays = [
    (self: _: {
      linuxPackages-rock5b = self.linuxPackagesFor (self.linux-rock5b.override (o: {
        argsOverride = old: {
          kernelPatches = old.kernelPatches ++ [{ patch = ./faster-pd.patch; }];
        };
      }));
    })
  ];

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = false;
  };

  networking = {
    hostName = "rock-5b";
    nameservers = [ "192.168.23.1" ];
    useNetworkd = true;
    useDHCP = false;

    # No local firewall.
    nat.enable = false;
    firewall.enable = false;
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    networks = {
      "10-lan" = {
        matchConfig.Name = "enP4p65s0";
        linkConfig.RequiredForOnline = "enslaved";
        dhcpV4Config.RouteMetric = 1;
        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = true;
        };
        address = [
          # configure addresses including subnet mask
          "192.168.23.11/24"
        ];
        routes = [
          { routeConfig.Gateway = "192.168.23.1"; }
        ];
      };
      "20-rescue" = {
        matchConfig.Name = "enu*";
        address = [
          # configure addresses including subnet mask
          "192.168.22.1/24"
        ];
        networkConfig = {
          IPv6AcceptRA = true;
        };
      };
      "30-wifi" = {
        matchConfig.Driver = "rt2800usb";
        address = [
          "192.168.23.250/24"
        ];
        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = true;
        };
        linkConfig.RequiredForOnline = "false";
      };
    };
  };

  networking.wireless = {
    enable = true;
    networks = {
      VM4588425 = {
        psk = "Jd6qrtjwnqrj";
      };
    };
  };

  services.dnsmasq = {
    enable = true;
    alwaysKeepRunning = true;
    settings = {
      interface = "enu1u1";
      dhcp-range = "192.168.22.2,192.168.22.254,24h";
    };
    extraConfig = ''
      bind-interfaces
    '';
  };

  environment.systemPackages = [ pkgs.iperf ];

  # require interface to be up before starting dnsmasq
  systemd.services.dnsmasq.after = [ "sys-subsystem-net-devices-enu1u1.device" ];

  services.irqbalance.enable = lib.mkDefault true;

  powerManagement.enable = false;
  # powerManagement.cpuFreqGovernor = lib.mkDefault " ondemand ";

  services.openssh.enable = true;
  services.openssh.permitRootLogin = "yes";

}
