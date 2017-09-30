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
    zfs
    mosh
    libvirt
  ];

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  services.openssh.forwardX11 = true;
  services.postgresql.enable = true;
  services.postgresql.enableTCPIP = true;
  services.postgresql.authentication = ''
    host  all  all 172.17.0.0/16 md5
  '';

  nix.maxJobs = lib.mkDefault 8;

  boot.initrd.availableKernelModules = [ "dm_mod" "zfs" ];
  boot.loader.grub.devices = [ "/dev/sda" "/dev/sdb" ];
  boot.loader.grub.timeout = 0;

  fileSystems."/boot" =
    { device = "zpool/boot";
      fsType = "zfs";
    };
  fileSystems."/" =
    { device = "zpool/root/nixos";
      fsType = "zfs";
    };

  imports = [
    ./nixos/16_03.nix
    ./kernels/latest.nix
    ./services/k8s.nix
    ./users.nix
  ];
}
