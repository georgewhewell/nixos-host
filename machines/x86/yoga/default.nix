{ config, pkgs, lib, ... }:

{

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/development.nix
    ../../../profiles/home.nix
    ../../../profiles/graphical.nix
    ../../../profiles/intel-gfx.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/thinkpad.nix
    ../../../services/buildfarm-executor.nix
    ../../../services/docker.nix
  ];

  sconfig = {
    profile = "desktop";
    home-manager = {
      enable = true;
      enableGraphical = true;
    };
    wireguard = {
      enable = true;
    };
  };

  deployment.allowLocalDeployment = true;

  boot = {
    #kernelPackages = pkgs.linuxPackages_latest_lto_skylake;
    loader.timeout = 1;

    blacklistedKernelModules = [
      "mei"
      "mei_me"
      "mei_wdt"
      "acer_wmi"
      "applesmc"
      "intel_backlight"
    ];

    kernelParams = [
      "video=eDP-1:d"
    ];

    initrd = {
      # Required to open the EFI partition and Yubikey
      kernelModules = [ "vfat" "nls_cp437" "nls_iso8859-1" "usbhid" ];

      luks = {
        # Support for Yubikey PBA
        yubikeySupport = true;

        devices."encrypted" = {
          device = "/dev/nvme0n1p3"; # Be sure to update this to the correct volume

          yubikey = {
            slot = 2;
            twoFactor = true; # Set to false for 1FA
            gracePeriod = 30; # Time in seconds to wait for Yubikey to be inserted
            keyLength = 64; # Set to $KEY_LENGTH/8
            saltLength = 16; # Set to $SALT_LENGTH

            storage = {
              device = "/dev/nvme0n1p1"; # Be sure to update this to the correct volume
              fsType = "vfat";
              path = "/crypt-storage/default";
            };
          };
        };
      };
    };
  };

  fileSystems."/" =
    {
      device = "/dev/mapper/encrypted";
      fsType = "ext4";
    };


  fileSystems."/boot" =
    {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
      options = [ "umask=007" ];
    };

  services.undervolt = {
    enable = true;
    tempAc = 97;
    tempBat = 75;
    coreOffset = -100;
    gpuOffset = -30;
    #uncoreOffset = -50;
    #analogioOffset = -50;
  };

  systemd.network = {
    enable = true;
    networks = {
      "10-wlan" = {
        matchConfig.Name = "wlp4s0";
        networkConfig.DHCP = "ipv4";
      };
    };
  };

  networking = {
    hostName = "yoga";
    nftables.enable = true;
    useNetworkd = true;
    firewall = {
      interfaces.wg0 = {
        allowedTCPPorts = [ 22 9090 9100 ];
      };
    };
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
}
