{ config, lib, pkgs, ... }:

{

  # cksum /etc/machine-id | while read c rest; do printf "%x" $c; done
  networking.hostId = "cd499340";
  networking.hostName = "tsar.su";

  time.timeZone = "Europe/London";
  networking.firewall.enable = true;

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
    libvirt
    zfs
    tor
  ];

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  services.munin-node.enable = true;

  services.fail2ban.enable = true;
  services.fail2ban.jails.ssh-iptables = "enabled = true";

  boot.initrd.availableKernelModules = [ "dm_mod" "zfs" ];
  boot.loader.grub.devices = ["/dev/sda" "/dev/sdb" ];
  boot.loader.grub.timeout = 0;

  fileSystems."/boot" =
    { device = "zpool/boot";
      fsType = "zfs";
    };

  fileSystems."/" =
    { device = "zpool/root/nixos";
      fsType = "zfs";
    };

  /*
  fileSystems."/var/lib/docker" =
    { device = "zpool/docker";
      fsType = "zfs";
    };
  */

  imports = [
    <nixpkgs/nixos/modules/installer/scan/not-detected.nix>
    ./nixos/16_03.nix
    ./kernels/4_2.nix

    ./services/tor-relay.nix
    ./users.nix
  ];
}
