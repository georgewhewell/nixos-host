{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  /*
  asrock n100 itx board
  */
  sconfig = {
    profile = "server";
    home-manager.enable = true;
  };

  system.stateVersion = "24.11";

  deployment.targetHost = "192.168.23.14";
  deployment.targetUser = "grw";

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-intel
    common-gpu-intel

    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/headless.nix
    # ../../../profiles/intel-gfx.nix
    ../../../profiles/uefi-boot.nix

    ../../../services/buildfarm-slave.nix
  ];

  hardware.firmware = [
    pkgs.wakiki-fw
  ];

  # Custom kernel from ath git repository for WiFi 7 support
  boot.kernelPackages = pkgs.linuxPackages_testing;

  # let
  #   athKernel = pkgs.linuxKernel.kernels.linux_latest.override {
  #     argsOverride = {
  #       src = pkgs.fetchgit {
  #         url = "https://git.kernel.org/pub/scm/linux/kernel/git/ath/ath.git";
  #         rev = "ath12k-ng";
  #         hash = "sha256-rneAiyNgZaFw7rDGr1ym3XIdUEI0WnAmf2J7a9lXX2o=";
  #       };
  #       version = "6.17-ath";
  #       modDirVersion = "6.16.0-ath12k-ng";
  #     };
  #     structuredExtraConfig = with lib.kernel; {
  #       # Disable removed/renamed option
  #       AMD_HFI = lib.mkForce unset;
  #       USB_XHCI_SIDEBAND = lib.mkForce unset;
  #       DAMON_STAT = lib.mkForce unset;
  #       NET_SCH_BPF = lib.mkForce unset;
  #     };
  #   };
  # in
  #   lib.mkForce (pkgs.linuxPackagesFor athKernel);

  services.hostapd = {
    enable = true;
    noScan = true;
    radios = {
      wlan0 = {
        band = "5g";
        countryCode = "CH";
        settings.country3 = "0x49"; # indoor
        settings.ieee80211w = 2;
        settings.sae_require_mfp = 1;
        channel = 165;
        settings.vht_oper_centr_freq_seg0_idx = config.services.hostapd.radios.wlan0.channel + 6;
        wifi4.enable = false;

        wifi5 = {
          enable = true;
          operatingChannelWidth = "80+80";
          capabilities = [
            "RXLDPC"
            "RX-STBC-1"
            "SHORT-GI-80"
            "TX-STBC-2BY1"
            "RX-STBC-1"
            "RX-ANTENNA-PATTERN"
            "TX-ANTENNA-PATTERN"
            "SU-BEAMFORMEE"
            "MU-BEAMFORMEE"
            "SU-BEAMFORMER"
            "MU-BEAMFORMER"
          ];
        };

        wifi6 = {
          enable = true;
          operatingChannelWidth = "80+80";
          multiUserBeamformer = true;
          singleUserBeamformee = true;
          singleUserBeamformer = true;
        };

        wifi7 = {
          enable = true;
          operatingChannelWidth = "20or40";
          multiUserBeamformer = true;
          singleUserBeamformee = true;
          singleUserBeamformer = true;
        };

        networks = {
          wlan0 = {
            ssid = "Radio Free Europe";
            authentication = {
              mode = "wpa3-sae";
              saePasswordsFile = "/tmp/password";
            };
            settings = {
              bridge = "br0.lan";
            };
          };
        };
      };
    };
  };

  # environment.systemPackages = with pkgs; [
  #   wirelesstools
  #   iw
  # ];

  # services.iperf3 = {
  #   enable = true;
  #   openFirewall = true;
  # };

  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = lib.mkForce true;
    };
  };

  fileSystems."/" = {
    device = "UUID=8b8990d8-15a7-4308-a51c-4e5b7a6898e1";
    fsType = "bcachefs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2A3E-BFEC";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom="CH"
  '';

  networking = {
    hostName = "n100";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    useDHCP = false;

    wireless = {
      enable = false; # exclusive with iwd
      iwd = {
        enable = true;
        settings = {
          IPv6 = {
            Enabled = true;
          };
          # Settings = {
          #   AutoConnect = true;
          # };
        };
      };
    };
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    netdevs = {
      "20-br-lan" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br0.lan";
        };
      };
    };

    networks = {
      "10-lan" = {
        matchConfig.Driver = "r8169";
        networkConfig = {
          Bridge = "br0.lan";
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "enslaved";
      };
      "40-br" = {
        matchConfig.Name = "br0.lan";
        networkConfig = {
          IPv6AcceptRA = true;
        };
        address = [
          "192.168.23.14/24"
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
}
