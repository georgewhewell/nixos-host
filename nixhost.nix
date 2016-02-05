{ config, lib, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;


  networking.hostName = "nixhost";
  networking.hostId = "dd499341";

  time.timeZone = "Europe/London";

  i18n = {
    consoleFont = "Lat2-Terminus16";
    defaultLocale = "en_GB.UTF-8";
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    iptables
    lm_sensors
    sdparm
    smartmontools
    libvirt
    zfs
  ];
  boot.kernelPackages = pkgs.linuxPackages_latest;

  services.avahi.enable = true;
  services.avahi.publish.enable = true;
  services.avahi.publish.addresses = true;
  services.avahi.nssmdns = true;

  services.openssh.enable = true;
  services.thermald.enable = true;
  services.munin-node.enable = true;

  hardware.pulseaudio.enable = true;

  services.redshift = {
    enable = true;
    latitude = "51.5";
    longitude = "-0.1";
  };

  services.fail2ban.enable = true;

  boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" "nvme" "dm_mod" "zfs" ];

  fileSystems."/boot" =
    { device = "/dev/nvme0n1p1";
      fsType = "vfat";
    };
  fileSystems."/" =
    { device = "zpool/nixos";
      fsType = "zfs";
    };
  fileSystems."/mnt/storage" =
    { device = "zpool/storage";
      fsType = "zfs";
    };
  fileSystems."/var/lib/docker" =
    { device = "zpool/docker";
      fsType = "zfs";
    };
  fileSystems."/mnt/Home" =
      { device = "zpool/Home";
        fsType = "zfs";
      };
  fileSystems."/mnt/Media" =
    { device = "zpool/Media";
      fsType = "zfs";
    };

  fileSystems."/config" =
    { device = "/dev/disk/by-id/dm-name-sm951-config";
      fsType = "btrfs";
    };

  boot.kernelParams = [
    "i915.preliminary_hw_support=1"
    "usbhid.mousepoll=1"
  ];

  boot.loader.gummiboot.enable = true;
  boot.loader.gummiboot.timeout = 1;
  boot.loader.efi.canTouchEfiVariables = true;

  imports = [
    ./i3.nix
    ./nixos/16_03.nix

    ./network/wlan.nix
    ./services/tinc.nix

    ./services/fancontrol.nix
    ./services/samba.nix
    ./services/docker.nix
    ./services/sonarr.nix
    ./services/couchpotato.nix
    ./services/transmission.nix
    ./services/upnpc.nix
    ./services/ethminer.nix

    ./users.nix
  ];
}
