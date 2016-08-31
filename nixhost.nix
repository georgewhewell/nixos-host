{ config, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "nixhost";
  networking.hostId = "ed499341";

  time.timeZone = "Europe/London";
  
  hardware.enableAllFirmware = true;
  hardware.firmware = [ pkgs.si2168_02 ];

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
si2168_02
  ];
  boot.kernelPackages = pkgs.linuxPackages_4_4;

  services.avahi.enable = true;
  services.avahi.publish.enable = true;
  services.avahi.publish.addresses = true;
  services.avahi.nssmdns = true;
  services.avahi.interfaces = [ "enp1s0" ];

  networking.firewall.enable = false;

  services.openssh.enable = true;
#  services.thermald.enable = true;
#  services.munin-node.enable = true;

  services.fail2ban.enable = true;

  boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" ];

  fileSystems."/" =
    { device = "/dev/sda3";
      fsType = "ext4";
    };
  fileSystems."/mnt/oldnix" =
    { device = "zpool/nixos";
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
  fileSystems."/mnt/storage" =
    { device = "zpool/storage";
      fsType = "zfs";
    };

  boot.loader.grub.enable = true;
  boot.loader.grub.devices = [ "/dev/sda" ];

  imports = [
 #   ./i3.nix
    ./nixos/16_03.nix
    ./modules/custom-packages.nix

#   ./network/wlan.nix
#   ./services/tinc.nix

#   ./services/collectd.nix
#   ./services/fancontrol.nix
    ./services/samba.nix
    ./services/docker.nix
    ./services/timemachine.nix
#   ./services/sonarr.nix
#   ./services/couchpotato.nix
#   ./services/transmission.nix
#   ./services/upnpc.nix
#   ./services/ethminer.nix

    ./users.nix
  ];

}
