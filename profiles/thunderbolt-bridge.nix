{ config, lib, pkgs, network, ... }:
let
  cfg = config.profiles.thunderbolt-bridge;
  bridgeName = "br0.lan";
  lanMtu = toString network.vlans.lan.mtu;

  # Common bridge config for USB/thunderbolt interfaces
  bridgeNetwork = {
    networkConfig.Bridge = bridgeName;
    linkConfig.RequiredForOnline = "enslaved";
  };

  # USB network drivers to bridge
  usbDrivers = [
    "rndis_host"    # Android/Windows USB tethering
    "cdc_ether"     # CDC Ethernet
    "cdc_eem"       # CDC Ethernet Emulation Model
    "cdc_subset"    # CDC subset
    "cdc_ncm"       # CDC Network Control Model
    "r8152"         # Realtek USB Gigabit
    "asix"          # ASIX USB ethernet
    "ax88179_178a"  # ASIX AX88179/178A
  ];
in {
  options.profiles.thunderbolt-bridge = {
    enableThunderboltNet = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Load the thunderbolt-net kernel module (thunderbolt-to-thunderbolt networking).";
    };
    bridgeThunderboltNet = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add thunderbolt-net interfaces to ${bridgeName}.
        When false, the interface is brought up with IPv4LL + mDNS (link-local
        only, no bridge, no DHCP), so peers can find each other via .local
        names without exposing them to the LAN.
      '';
    };
  };

  config = {
    boot.kernelModules = lib.optional cfg.enableThunderboltNet "thunderbolt-net";
    # Without this, udev still pulls thunderbolt-net in via the
    # tbsvc:knetworkp00000001 modalias the moment any xdomain peer
    # advertises the network service — it then claims a controller
    # hop and starves out usb4_rdma's data-path lanes.
    boot.blacklistedKernelModules = lib.optional (!cfg.enableThunderboltNet) "thunderbolt_net";

    services.hardware.bolt.enable = true;

    # USB device symlinks and permissions
    services.udev.extraRules = ''
      # Disable problematic USB device
      SUBSYSTEM=="usb", ATTRS{idVendor}=="13d3", ATTRS{idProduct}=="3404", ATTR{authorized}="0"

      # Bootloader/flasher device symlinks
      SUBSYSTEM=="usb", ATTRS{idVendor}=="04e8", ATTRS{idProduct}=="1234", GROUP="users", MODE="0660", SYMLINK+="usb-loader-m3"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="1f3a", ATTRS{idProduct}=="efe8", GROUP="users", MODE="0660", SYMLINK+="sunxi-fel"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="2207", ATTRS{idProduct}=="330c", GROUP="users", MODE="0660", SYMLINK+="rockchip-rk3399"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0e8d", ATTRS{idProduct}=="2000", ENV{ID_MM_DEVICE_IGNORE}="1", GROUP="users", MODE="0660", SYMLINK+="mtk-preloader"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="0483", GROUP="users", MODE="0660", SYMLINK+="stm32"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", GROUP="users", MODE="0660", SYMLINK+="stm32-dfu"

      # VIA Labs, Inc. USB3.0 Hub
      SUBSYSTEM=="usb", ATTRS{idVendor}=="2109", ATTRS{idProduct}=="2811", GROUP="users", MODE="0660", SYMLINK+="smart-hub"
    '';

    systemd.network = {
      links = {
        # USB network: disable offloads and power management
        "50-usb-net" = {
          matchConfig.Driver = lib.concatStringsSep " " usbDrivers;
          linkConfig = {
            GenericReceiveOffload = false;
            GenericSegmentationOffload = false;
            TCPSegmentationOffload = false;
            WakeOnLan = "off";
          };
        };
      } // lib.optionalAttrs cfg.enableThunderboltNet {
        # Thunderbolt: disable offloads for bridging stability, don't change MAC
        "50-thunderbolt" = {
          matchConfig.Driver = "thunderbolt-net";
          linkConfig = {
            GenericReceiveOffload = false;
            GenericSegmentationOffload = false;
            TCPSegmentationOffload = false;
            MACAddressPolicy = "none";
          } // lib.optionalAttrs cfg.bridgeThunderboltNet {
            MTUBytes = lanMtu;
          };
        };
      };

      networks = {
        # Exclude BMC virtual ethernet (American Megatrends ID_VENDOR_ID=046b)
        "49-bmc-exclude" = {
          matchConfig = {
            Driver = "cdc_ether";
            Property = "ID_VENDOR_ID=046b";
          };
          linkConfig.Unmanaged = "yes";
        };

        # USB network adapters - bridge to LAN
        # Note: Router has its own higher-priority 20-nanokvm config for NanoKVM
        "50-rndis" = { matchConfig.Driver = "rndis_host"; } // bridgeNetwork;
        "50-cdc-ether" = { matchConfig.Driver = "cdc_ether"; } // bridgeNetwork;
        "50-cdc-eem" = { matchConfig.Driver = "cdc_eem"; } // bridgeNetwork;
        "50-cdc-subset" = { matchConfig.Driver = "cdc_subset"; } // bridgeNetwork;
        "50-cdc-ncm" = { matchConfig.Driver = "cdc_ncm"; } // bridgeNetwork;
        "50-r8152" = { matchConfig.Driver = "r8152"; } // bridgeNetwork;
        "50-asix" = { matchConfig.Driver = "asix"; } // bridgeNetwork;
        "50-ax88179" = { matchConfig.Driver = "ax88179_178a"; } // bridgeNetwork;

        # iPhone tethering - failover internet with high metric (NOT bridged)
        "60-iphone-tether" = {
          matchConfig.Driver = "ipheth";
          networkConfig = {
            DHCP = "yes";
            IPv6AcceptRA = true;
          };
          dhcpV4Config.RouteMetric = 2048;
          ipv6AcceptRAConfig.RouteMetric = 2048;
          linkConfig.RequiredForOnline = "no";
        };
      } // lib.optionalAttrs cfg.enableThunderboltNet {
        # Thunderbolt networking. Hot-plug, so never required-for-online.
        "50-thunderbolt" = {
          matchConfig.Driver = "thunderbolt-net";
        } // (
          if cfg.bridgeThunderboltNet
          then bridgeNetwork // { linkConfig.RequiredForOnline = "no"; }
          else {
            networkConfig = {
              LinkLocalAddressing = "yes";
              MulticastDNS = "yes";
              LLMNR = "yes";
              DHCP = "no";
              IPv6AcceptRA = false;
            };
            linkConfig.RequiredForOnline = "no";
          }
        );
      };
    };
  };
}
