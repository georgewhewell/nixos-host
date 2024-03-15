{ config, pkgs, lib, ... }:

{
  /*
    fuckup: skylake desktop
  */
  sconfig = {
    profile = "desktop";
    home-manager = {
      enable = true;
      enableGraphical = true;
      enableVscodeServer = true;
    };
  };

  environment.systemPackages = [
    pkgs.gparted
  ];

  nixpkgs.config.permittedInsecurePackages = [
    "nodejs-16.20.1"
    "nodejs-16.20.2"
    "nix-2.15.3"
  ];

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/development.nix
      ../../../profiles/bridge-interfaces.nix
      ../../../profiles/home.nix
      ../../../profiles/nas-mounts.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/graphical.nix
      ../../../profiles/radeon.nix
      ../../../profiles/intel-gfx.nix
      ../../../profiles/fastlan.nix

      ../../../services/buildfarm-slave.nix
      ../../../services/buildfarm-executor.nix

      ../../../services/virt/host.nix
      # ../../../services/virt/vfio.nix
    ];

  boot.kernelPackages = pkgs.linuxPackages_latest_lto_skylake;
  # boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelParams = [
    "pci=realloc"
    "libata.force=4.00:noncq"
    "libata.force=4.00:3.0Gbps"
    "libata.force=5.00:noncq"
    "libata.force=5.00:3.0Gbps"
  ];

  system.stateVersion = "22.11";
  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };
  fileSystems."/" =
    {
      device = "/dev/mapper/vg1-nixos";
      fsType = "f2fs";
    };

  fileSystems."/home/grw" =
    {
      device = "/dev/mapper/vg1-home";
      fsType = "f2fs";
    };

  fileSystems."/boot" =
    {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
    };

  environment.etc."OpenCL/vendors" = {
    mode = "symlink";
    source = "/run/opengl-driver/etc/OpenCL/vendors";
  };

  nix.settings.max-jobs = lib.mkDefault 8;
  #powerManagement.cpuFreqGovernor = "performance";

  networking = {
    hostName = "fuckup";
    wireless.enable = false;
    useDHCP = false;
    enableIPv6 = true;

    firewall = {
      enable = true;
      allowedTCPPortRanges = [{ from = 5000; to = 5005; } { from = 50000; to = 60000; }];
      allowedUDPPortRanges = [{ from = 6000; to = 6005; } { from = 35000; to = 65535; }];
      allowedUDPPorts = [ 111 5353 40601 ];
      allowedTCPPorts = [
        9100
        10809
        8880
        8080
        /* shairport */
        3689
        5353

        39375 # ?? lol
        36383
        41815 # nfs??
        45085
        57747 # rpcinfo -p
      ];
      checkReversePath = false;
      extraCommands = ''
        ${pkgs.iptables}/bin/iptables -I INPUT -p igmp -j ACCEPT
      '';
    };

    interfaces.br0 = {
      useDHCP = true;
    };

    bridges.br0 = {
      interfaces = [
        "enp0s31f6" # onboard ethernet
        # "enp5s0u2u1"
      ];
    };
  };
}
