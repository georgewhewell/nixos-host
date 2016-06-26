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
  networking.firewall.trustedInterfaces = [ "docker0" ];
  networking.firewall.allowedUDPPorts = [ 25826 ];

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
  ];

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  services.postgresql.enable = true;
  services.postgresql.enableTCPIP = true;
  services.postgresql.authentication = ''
    host  all  all 172.17.0.0/16 md5
  '';
  services.redis.enable = true;

  #services.influxdb.enable = true;
  #services.influxdb.extraConfig.collectd.enabled = true;

  # services.fail2ban.enable = true;
  # services.fail2ban.jails.ssh-iptables = "enabled = true";

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
    { device = "/dev/zpool/docker_ext4";
      fsType = "ext4";
    };
  fileSystems."/var/lib/kubelet" =
    { device = "/dev/zpool/kubelet";
      fsType = "xfs";
    };

  imports = [
    ./nixos/16_03.nix
    ./kernels/latest.nix

#    ./services/tinc.nix
    ./services/docker.nix
#    ./services/openvpn.nix
#    ./services/openvpn-native.nix
    ./services/jupyter.nix
    ./services/sslh.nix

    #./services/k8s.nix
    ./services/tor-client.nix
    ./services/tor-relay.nix
    ./services/gogs.nix
    ./services/drone.nix
    ./services/sentry.nix
   # ./services/collectd.nix
#    ./services/grafana.nix
    ./services/nginx.nix

    ./users.nix
  ];
}
