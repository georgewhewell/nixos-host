{ config, lib, pkgs, ... }:

{
  networking.hostName = "nixhost";
  time.timeZone = "Europe/London";
  networking.firewall.enable = false;

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
  ];

  security.sudo.wheelNeedsPassword = false;

  services.avahi.enable = true;
  services.avahi.nssmdns = true;
  services.openssh.enable = true;
  services.thermald.enable = true;
  services.munin-node.enable = true;
  services.fail2ban.enable = true;
  services.fail2ban.jails.ssh-iptables = "enabled = true";

  boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" "nvme" "dm_mod" ];

  fileSystems."/boot" =
    { device = "/dev/nvme0n1p1";
      fsType = "vfat";
    };

  fileSystems."/" =
    { device = "/dev/disk/by-id/dm-name-sm951-nixos";
      fsType = "ext4";
    };

  fileSystems."/backups" =
    { device = "/dev/sdb1";
      fsType = "ext4";
    };

  fileSystems."/storage" =
    { device = "/dev/disk/by-id/dm-name-evo-storage";
      fsType = "btrfs";
    };

  fileSystems."/config" =
    { device = "/dev/disk/by-id/dm-name-sm951-config";
      fsType = "btrfs";
    };

  imports = [
    <nixpkgs/nixos/modules/installer/scan/not-detected.nix>
    ./hardware/efiboot.nix

    ./kernels/testing.nix

    ./network/wlan.nix

    ./nixos/16_03.nix

    ./services/fancontrol.nix
    ./services/nfs.nix
    ./services/transmission.nix

    ./services/docker.nix
    ./services/sonarr.nix
    ./services/couchpotato.nix

    ./services/virt/host.nix
    ./services/backup.nix

    ./users.nix
  ];
}
