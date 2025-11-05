{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  system.stateVersion = "25.05";

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/pray-for-sd-card.nix
    ../../../services/buildfarm-slave.nix
  ];

  sconfig = {
    profile = "server";
    home-manager.enable = true;
    xmrig.enable = false;
  };

  deployment.targetHost = "192.168.23.18";
  # deployment.targetHost = "rock-5b.lan.satanic.link";
  deployment.targetUser = "grw";

  disko.devices = {
    disk = {
      p1600x = {
        device = "/dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_PHOC331301BN118B";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "512M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "btrfs";
                mountpoint = "/";
                mountOptions = ["relatime"];
              };
            };
          };
        };
      };
    };
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    extraModprobeConfig = ''
      options cfg80211 ieee80211_regdom="CH"
      options iwlwifi power_save=1 11n_disable=1
      options iwlmvm power_scheme=1
    '';
    kernelParams = [
      "console=ttyS2,1500000n8"
      "pcie_aspm=off"
    ];
    loader = {
      grub.enable = false;
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      timeout = 1;
    };
    initrd = {
      systemd = {
        enable = true;
        emergencyAccess = true;
        network.enable = true;

        services.pcie-rescan = {
          description = "Rescan PCIe bus for NVMe detection";
          after = ["modprobe@nvme.service"];
          before = ["systemd-udev-settle.service"];
          wantedBy = ["initrd.target"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.bash}/bin/bash -c 'echo 1 > /sys/bus/pci/rescan && sleep 2'";
            RemainAfterExit = true;
          };
        };
      };

      kernelModules = [
        "nvme"
        "r8169"
        "phy_rockchip_naneng_combphy"
      ];

      availableKernelModules = [
        "phy_rockchip_naneng_combphy"
        "mmc_core"
        "mmc_block"
      ];
    };
  };

  services.udev.extraRules = ''
    # Disable EEE when r8169 ethernet interface comes up
    ACTION=="add", SUBSYSTEM=="net", DRIVERS=="r8169", RUN+="${pkgs.ethtool}/bin/ethtool --set-eee $name eee off"

    # Disable power save on WiFi interfaces
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="${pkgs.iw}/bin/iw dev $name set power_save off"
  '';

  # Service to add policy routing when WiFi gets an IP
  systemd.services.wifi-policy-route = {
    description = "Add policy routing for WiFi interface";
    after = ["network-online.target"];
    requires = ["network-online.target"];
    wantedBy = ["multi-user.target"];

    path = [pkgs.iproute2 pkgs.gawk pkgs.gnugrep pkgs.coreutils];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
    };

    script = ''
      # Function to set up routing for current IP
      setup_routing() {
        IP=$(ip -4 addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)

        if [ -n "$IP" ]; then
          echo "Setting up policy routing for wlan0 IP: $IP"

          # Remove any existing rule for this IP
          ip rule del from "$IP" table 100 2>/dev/null || true

          # Add policy routing rule
          ip rule add from "$IP" table 100 priority 99

          # Ensure route exists in table 100
          ip route replace default via 192.168.23.1 dev wlan0 table 100

          echo "Policy routing configured for $IP"
        fi
      }

      # Wait for wlan0 to come up
      while ! ip link show wlan0 &>/dev/null; do
        sleep 5
      done

      # Set up routing for existing IP (if any)
      setup_routing

      # Monitor for IP address changes
      ip monitor address dev wlan0 | while read -r line; do
        if echo "$line" | grep -q "inet .* scope global"; then
          sleep 1  # Give time for address to stabilize
          setup_routing
        fi
      done
    '';
  };

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  hardware = {
    wirelessRegulatoryDatabase = true;
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };

  networking = {
    hostName = "rock-5b";
    nameservers = ["192.168.23.1"];
    useNetworkd = true;

    useDHCP = false;
    nat.enable = false;
    firewall.enable = true;

    wireless = {
      enable = false; # exclusive with iwd
      iwd = {
        enable = true;
        settings = {
          IPv6 = {
            Enabled = true;
          };
        };
      };
    };
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    networks = {
      # Ethernet with static IP
      "10-lan" = {
        matchConfig.Driver = "r8169";
        address = [
          "192.168.23.18/24"
        ];
        routes = [
          {
            Gateway = "192.168.23.1";
            Metric = 1;
          }
        ];
        linkConfig.RequiredForOnline = "routable";
      };
      # WiFi with DHCP
      "20-wifi" = {
        matchConfig.Type = "wlan";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.RouteMetric = 200;
        linkConfig.RequiredForOnline = "no";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    iperf
    bcachefs-tools
    lshw
    pciutils
    usbutils
    wirelesstools
    iw
    iwd
    powertop
    stress-ng
  ];

  services.irqbalance.enable = lib.mkDefault true;

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "ondemand";
    # powertop.enable = true;
  };

  services.getty.autologinUser = "root";

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 10;
    freeSwapThreshold = 10;
    enableNotifications = false;
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
}
