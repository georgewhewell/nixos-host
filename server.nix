{ config, lib, pkgs, ... }:

{

  # cksum /etc/machine-id | while read c rest; do printf "%x" $c; done
  networking.hostId = "cd499340";
  networking.hostName = "tsar.su";
  environment.interactiveShellInit = ''
    # A nix query helper function
    nq()
    {
      case "$@" in
        -h|--help|"")
          printf "nq: A tiny nix-env wrapper to search for packages in package name, attribute name and description fields\n";
          printf "\nUsage: nq <case insensitive regexp>\n";
          return;;
      esac
      nix-env -qaP --description \* | grep -i "$@"
    }
    export HISTCONTROL=ignoreboth   # ignorespace + ignoredups
    export HISTSIZE=1000000         # big big history
    export HISTFILESIZE=$HISTSIZE
    shopt -s histappend             # append to history, don't overwrite it
  '';

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
  security.pam.loginLimits = [
    { domain = "redis"; item = "nofile"; type = "soft"; value = 65536; }
    { domain = "redis"; item = "nofile"; type = "hard"; value = 65536; }
  ];

  services.fail2ban.enable = true;
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
    { device = "zpool/docker";
      fsType = "zfs";
    };

  imports = [
    <nixpkgs/nixos/modules/installer/scan/not-detected.nix>
    ./nixos/16_03.nix
    ./kernels/latest.nix

    ./services/tinc.nix
    ./services/docker.nix
    ./services/openvpn.nix

    ./services/kinto.nix
    ./services/tor-relay.nix
    ./services/gogs.nix
    ./services/drone.nix
    ./services/sentry.nix
    ./services/grafana.nix
    ./services/nginx.nix

    ./users.nix
  ];
}
