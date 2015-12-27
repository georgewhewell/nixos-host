{ config, lib, pkgs, ... }:

{

  # cksum /etc/machine-id | while read c rest; do printf "%x" $c; done
  networking.hostId = "cd499340";
  networking.hostName = "tsar.su";

boot.kernel.sysctl = {
"net.core.wmem_max"=12582912;
"net.core.rmem_max"=12582912;
"net.ipv4.tcp_rmem"="10240 87380 12582912";
"net.ipv4.tcp_wmem"="10240 87380 12582912";
"net.core.netdev_max_backlog"=5000;
};

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
    mosh
  ];

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  services.munin-cron.enable = true;
  services.munin-cron.hosts = ''
   [tsar.su]
   address localhost
   [nixhost]
   address ssh://86.3.184.2/run/current-system/sw/bin/nc localhost 4949
  '';
  services.postgresql.enable = true;
  services.postgresql.enableTCPIP = true;
  services.postgresql.authentication = ''
    host  all  all 172.17.0.0/16 md5
  '';
  services.munin-node.enable = true;
  services.redis.enable = true;
  services.redis.bind = "172.17.42.1";

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
  fileSystems."/var/lib/docker" =
    { device = "zpool/docker";
      fsType = "zfs";
    };

  imports = [
    <nixpkgs/nixos/modules/installer/scan/not-detected.nix>
    ./nixos/16_03.nix
    ./kernels/4_2.nix

    ./services/tinc.nix
    ./services/docker.nix
    ./services/openvpn.nix
#    ./services/transmission.nix

    ./services/tor-relay.nix
    ./services/docker-registry.nix
    ./services/gogs.nix
    ./services/drone.nix
    ./services/sentry.nix
    ./services/nginx.nix

    ./users.nix
  ];
}
