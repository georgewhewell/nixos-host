{ config, lib, pkgs, ... }:

let
  cfg = config.sconfig.hetzner;
in
{
  options.sconfig.hetzner.enable = lib.mkEnableOption "Enable hetzner config";
  options.sconfig.hetzner.luksUuid = lib.mkOption { };
  options.sconfig.hetzner.interface = lib.mkOption { };
  options.sconfig.hetzner.wgAddress = lib.mkOption { };

  options.sconfig.hetzner.ipv4 = {
    interface = lib.mkOption { };
    address = lib.mkOption { };
    gateway = lib.mkOption { };
    netmask = lib.mkOption { };
  };
  options.sconfig.hetzner.ipv6 = {
    address = lib.mkOption { };
  };

  config = lib.mkIf cfg.enable {
    fileSystems."/boot" =
      {
        device = "/dev/disk/by-label/boot";
        fsType = "ext4";
      };

    fileSystems."/" =
      {
        device = "/dev/disk/by-label/root";
        fsType = "ext4";
      };

    boot = {
      kernel.sysctl = {
        "net.core.rmem_default" = 134217728;
        "net.core.rmem_max" = 134217728;
        "net.core.wmem_default" = 134217728;
        "net.core.wmem_max" = 134217728;
        "vm.max_map_count" = 1000000;
      };
      loader = {
        systemd-boot.enable = false;
        grub = {
          enable = true;
          efiSupport = false;
          devices = [ "/dev/nvme0n1" "/dev/nvme1n1" ];
        };
      };
      kernelParams = [
        "ip=${cfg.ipv4.address}::${cfg.ipv4.gateway}:${cfg.ipv4.netmask}:${config.networking.hostName}-initrd:${cfg.interface}:off:1.1.1.1"
      ];
      kernelModules = [ "kvm-amd" "nvme" "r8169" "igb" ];
      initrd = {
        services.swraid.mdadmConf = config.environment.etc."mdadm.conf".text;
        kernelModules = [ "ahci" "nvme" "r8169" "igb" ];
        network = {
          enable = true;
          ssh = {
            enable = true;
            port = 2222;
            authorizedKeys = config.users.users.root.openssh.authorizedKeys.keys;
            hostKeys = [ /etc/nixos/secrets/ssh_host_ed25519_key ];
          };
          postCommands = ''
            echo 'cryptsetup-askpass' >> /root/.profile
          '';
        };
        luks = {
          mitigateDMAAttacks = true;
          cryptoModules = [ "aes" "xts" "sha256" "sha512" "cbc" ];
          devices."encrypted" = {
            device = "/dev/disk/by-uuid/${cfg.luksUuid}";
            preLVM = true;
            allowDiscards = true;
            bypassWorkqueues = true;
          };
        };
      };
    };

    environment.etc."mdadm.conf".text = ''
      HOMEHOST <ignore>
    '';

    systemd.services."wireguard-wg0".after = [ "wg-${config.networking.hostName}.secret-key.service" ];
    systemd.services."wireguard-wg0".requires = [ "wg-${config.networking.hostName}.secret-key.service" ];

    services.prometheus.exporters = {
      node = {
        enable = true;
        enabledCollectors = [ "systemd" ];
      };
      postgres = {
        enable = true;
        extraFlags = [ "--auto-discover-databases" ];
      };
      nginx = {
        enable = true;
      };
    };

    deployment.keys =
      {
        "wg-${config.networking.hostName}.secret" = {
          keyCommand = [ "pass" "wg-${config.networking.hostName}" ];
          destDir = "/run/keys";
          uploadAt = "pre-activation";
        };
      };

    networking = {
      wireless.enable = false;
      useDHCP = false;
      wireguard = {
        enable = true;
        interfaces = {
          wg0 = {
            ips = [ "${cfg.wgAddress}/24" ];
            listenPort = 51820;
            privateKeyFile = "/run/keys/wg-${config.networking.hostName}.secret";
            peers = [
              {
                publicKey = "SYHzYVpBDi8annhVGqvroQJLacRLTcmdDgQq4JlSDCs=";
                endpoint = "satanic.link:51820";
                allowedIPs = [ "192.168.24.1/32" "192.168.23.0/24" ];
                persistentKeepalive = 25;
              }
              {
                publicKey = "J2PvJjxRS5hZg/t5ZJk8u0yqy6MAyhzL1wvKZC8By1Y=";
                endpoint = "ax101.satanic.link:51820";
                allowedIPs = [ "192.168.24.2/32" ];
                persistentKeepalive = 25;
              }
            ];
          };
        };
      };

      interfaces = {
        "${cfg.interface}" = {
          ipv4.addresses = [
            {
              address = cfg.ipv4.address;
              prefixLength = 24;
            }
          ];
          ipv6.addresses = [
            {
              address = cfg.ipv6.address;
              prefixLength = 64;
            }
          ];
        };
      };

      defaultGateway = cfg.ipv4.gateway;
      defaultGateway6 = { address = "fe80::1"; inherit (cfg) interface; };
      nameservers = [ "1.1.1.1" ];
      extraHosts =
        ''
          192.168.24.2 ax101.lan
        '';
      firewall = {
        trustedInterfaces = [ "wg0" ];
        logRefusedConnections = false;
        interfaces."${cfg.interface}" = {
          allowedTCPPorts = [ 22 51820 ];
          allowedUDPPorts = [ 51820 ];
        };
      };
    };

    hardware.rasdaemon = {
      enable = true;
      extraModules = [ "amd64_edac" "edac_mce_amd" "edac_core" ];
    };
  };
}
