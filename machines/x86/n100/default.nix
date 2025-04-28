{
  pkgs,
  lib,
  ...
}: {
  /*
  asrock n100 itx board
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = false;
    };
  };

  system.stateVersion = "24.11";

  deployment.targetHost = "n100.satanic.link";
  deployment.targetUser = "grw";

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/headless.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/intel-gfx.nix

    ../../../services/buildfarm-slave.nix
    ../../../services/home-assistant/default.nix
  ];

  hardware.firmwareCompression = "none";
  hardware.enableAllFirmware = true;
  hardware.firmware = [
    pkgs.wakiki-fw
  ];

  services.hostapd = {
    enable = true;
    radios = {
      wlan0 = {
        band = "5g";
        countryCode = "CH";
        channel = 36;
        # settings.he_oper_chwidth = 2;
        settings.country3 = "0x49"; # indoor
        # settings.op_class = 134; # 160 MHz channe
        # settings.ieee80211w = 2;
        # settings.sae_require_mfp = 1;
        # settings.vht_oper_centr_freq_seg0_idx = 155;
        wifi4.enable = true;
        wifi5 = {
          enable = true;
          operatingChannelWidth = "80";
          capabilities = [
            # "MAX-MPDU-11454"
            # "SUPPORTED-CHANNEL-WIDTH-160"
            "RXLDPC"
            "SHORT-GI-80"
            # "SHORT-GI-160"
            "TX-STBC-2BY1"
            "SU-BEAMFORMEE"
            "MU-BEAMFORMEE"
          ];
        };
        wifi6 = {
          enable = true;
          #   # operatingChannelWidth = "160";
        };
        wifi7 = {
          enable = true;
          #   operatingChannelWidth = "160";
        };

        networks = {
          wlan0 = {
            ssid = "Radio Liberty";
            authentication = {
              mode = "wpa3-sae";
              saePasswordsFile = "/tmp/password";
            };
            bssid = "36:b2:ff:ff:ff:ff";
            settings = {
              bridge = "br0.lan";
            };
          };
        };
      };
    };
  };

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = lib.mkForce true;
    };
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    initrd.kernelModules = [
      "bcachefs"
      "ixgbe"
      "r8169"
      "nfsv4"
    ];
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

  environment.systemPackages = with pkgs; [
    wirelesstools
    iw
  ];

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
