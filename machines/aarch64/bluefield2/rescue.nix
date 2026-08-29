{
  config,
  pkgs,
  lib,
  modulesPath,
  network,
  ...
}: let
  self = network.hosts.bluefield2;
  oobMac = lib.toLower self.mac;
  bluefieldKernelConfig = with lib.kernel; {
    MELLANOX_PLATFORM = yes;
    MLXBF_BOOTCTL = module;
    MLXBF_PMC = module;
    MLXBF_TMFIFO = module;
  };
  bluefieldKernelPackages = pkgs.linuxPackagesFor (pkgs.linux.override {
    structuredExtraConfig = bluefieldKernelConfig;
  });
in {
  imports = [
    (modulesPath + "/installer/netboot/netboot.nix")
    ../../../profiles/users.nix
  ];

  system.stateVersion = "25.05";

  sconfig.profile = "server";

  networking = {
    hostName = "bluefield2-rescue";
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
    networkmanager.enable = lib.mkForce false;
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;

    networks = {
      "10-bluefield-oob" = {
        matchConfig.MACAddress = oobMac;
        address = [
          (network.cidrOf "lan" self.addresses.lan)
        ];
        dns = [network.dnsIp];
        routes = [
          {
            Gateway = network.routerIp;
            Metric = 1;
          }
        ];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "ipv6";
        };
        linkConfig.RequiredForOnline = "routable";
      };

      "20-bluefield-tmfifo" = {
        matchConfig.Driver = "virtio_net";
        address = [
          "192.168.100.2/30"
        ];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
        linkConfig.RequiredForOnline = "no";
      };
    };
  };

  boot = {
    kernelPackages = bluefieldKernelPackages;
    kernelParams = [
      "console=hvc0"
      "console=ttyAMA0,115200n8"
      "earlycon=pl011,0x01000000"
      "modprobe.blacklist=mlx5_core,mlx5_ib,mlxfw"
    ];

    supportedFilesystems = ["vfat" "ext4"];

    initrd.availableKernelModules = [
      "dw_mmc"
      "dw_mmc-bluefield"
      "dw_mmc-pltfm"
      "sdhci_acpi"
      "sdhci-of-dwcmshc"
      "mmc_block"
      "mlxbf_gige"
      "mlxbf-tmfifo"
      "virtio_console"
      "virtio_net"
    ];

    kernelModules = [
      "dw_mmc-bluefield"
      "mmc_block"
      "mlxbf_gige"
      "mlxbf-tmfifo"
      "virtio_console"
      "virtio_net"
    ];
  };

  services.getty.autologinUser = lib.mkForce "root";

  programs.zsh.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  users.users.root.openssh.authorizedKeys.keys =
    config.users.users.grw.openssh.authorizedKeys.keys;

  environment.systemPackages = with pkgs; [
    dosfstools
    e2fsprogs
    efibootmgr
    ethtool
    iproute2
    kmod
    mstflint
    pciutils
    tmux
    usbutils
    vim
  ];

  nix.settings = {
    build-cores = 2;
    max-jobs = 0;
  };
}
