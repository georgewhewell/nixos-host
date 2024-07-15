{ config, pkgs, lib, ... }:

{
  /*
    nixhost: xeon-d microserver
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = true;
    };
  };

  deployment.targetHost = "nixhost.satanic.link";
  deployment.targetUser = "grw";

  imports =
    [
      ../../../containers/radarr.nix
      ../../../containers/sonarr.nix

      ../../../profiles/common.nix
      ../../../profiles/crypto
      ../../../profiles/development.nix
      ../../../profiles/headless.nix
      ../../../profiles/home.nix
      ../../../profiles/logserver.nix
      ../../../profiles/nas.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/fastlan.nix

      ../../../services/buildfarm-slave.nix
      ../../../services/grafana.nix
      ../../../services/home-assistant/default.nix
      ../../../services/nginx.nix
      ../../../services/transmission.nix
      ../../../services/virt/host.nix
    ];

  services.tor = {
    enable = true;
    openFirewall = true;

    client = {
      enable = true;
      transparentProxy.enable = true;
      socksListenAddress = {
        IsolateDestAddr = true;
        addr = "0.0.0.0";
        port = 9050;
      };
    };

    relay = {
      enable = true;
      role = "bridge";
    };

    settings = {
      ORPort = 9999;
      ControlPort = 9051;
      SocksPolicy = [ "accept *:*" ];
    };
  };

  # boot.zfs.enableUnstable = true;
  # boot.kernelPackages = pkgs.linuxPackages_lto_broadwell;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  boot.zfs.requestEncryptionCredentials = false;

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  services.qbittorrent = {
    enable = true;
    openFirewall = true;
  };

  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
  ];

  boot.supportedFilesystems = [ "zfs" ];
  boot.binfmt.emulatedSystems = [ "aarch64-linux" "armv7l-linux" ];
  boot.kernelParams = [
    "pci=nocrs"
    # https://bugzilla.kernel.org/show_bug.cgi?id=203475#c61
    "libata.force=5:3.0Gbps"
    "libata.force=6:3.0Gbps"
    "libata.force=5:noncq,noncqtrim"
    "libata.force=6:noncq,noncqtrim"

    # optane zil/l2arc
    # "zfs.zfs_immediate_write_sz=${toString (128 * 1024 * 1024)}"
    # "zfs.l2arc_feed_min_ms=15"
    # "zfs.l2arc_nopreFfetch=1"
    # "zfs.l2arc_write_boost=${toString (2 * 1024 * 1024 * 1024)}"
    # "zfs.l2arc_write_max=${toString (2 * 1024 * 1024 * 1024)}"
    # "zfs.zfs_arc_max=12884901888"
  ];

  services.dnscrypt-proxy2 = {
    enable = true;
    settings = {
      listen_addresses = [ "127.0.0.1:54" ];
      static.cloudflare = {
        stamp = "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
      };
      # blacklist.blacklist_file = "${pkgs.sources.hosts-blocklists}/dnscrypt-proxy/dnscrypt-proxy.blacklist.txt";
    };
  };

  services.dnsmasq =
    let
      lanBridge = "br0.lan";
    in
    {
      enable = true;
      servers = [ "127.0.0.1#54" ];
      extraConfig = ''
        domain-needed
        bogus-priv
        no-resolv
        no-hosts
        log-dhcp
        domain=satanic.link
        local=/satanic.link/
        bind-interfaces
        interface=${lanBridge}
        dhcp-range=${lanBridge},192.168.23.20,192.168.23.249,6h
        dhcp-option=${lanBridge},3,192.168.23.1    # send default gateway

        dhcp-host=e4:8d:8c:a8:de:40,192.168.23.2   # 10gb switch
        dhcp-host=80:2a:a8:80:96:ef,192.168.23.3   # ap
        dhcp-host=0c:c4:7a:89:fb:37,192.168.23.4   # x10 ipmi
        dhcp-host=0c:c4:7a:87:b9:d8,192.168.23.5   # nixhost
        dhcp-host=78:11:dc:ec:86:ea,192.168.23.6   # vacuum
        dhcp-host=06:f1:3e:03:27:8c,192.168.23.7   # fuckup
        dhcp-host=50:6b:4b:03:04:cb,192.168.23.8   # trex
        dhcp-host=48:A9:8A:93:42:4C,192.168.23.9   # 100gb switch
        dhcp-host=9c:6b:00:57:31:77,192.168.23.10  # trx90bmc
        dhcp-host=28:29:86:8b:3f:cb,192.168.23.11  # apc ups
        dhcp-host=b4:22:00:cf:18:63,192.168.23.12  # printer
        dhcp-host=c8:f0:9e:de:3c:2f,192.168.23.13  # cerberus

        # hosted names
        address=/router/192.168.23.254
        address=/nixhost/192.168.23.5
        address=/fuckup/192.168.23.7
        address=/trex/192.168.23.8
        address=/cloud/192.168.24.2
        address=/jellyfin/192.168.23.206
        address=/^satanic.link/192.168.23.254
        address=/grafana.satanic.link/192.168.23.5
        address=/home.satanic.link/192.168.23.5
        address=/jellyfin.satanic.link/192.168.23.5
        address=/paperless.satanic.link/192.168.23.5
        address=/radarr.satanic.link/192.168.23.5
        address=/sonarr.satanic.link/192.168.23.5
        address=/eth-mainnet.satanic.link/192.168.23.5
        address=/eth-mainnet-ws.satanic.link/192.168.23.5
        address=/hellas-mock-rpcserver.satanic.link/192.168.23.5
        address=/hellas-finetune-api.satanic.link/192.168.23.5
        address=/static.satanic.link/192.168.23.5
        address=/gateway.satanic.link/192.168.23.5
      '';
    };

  networking = {
    hostName = "nixhost";
    hostId = lib.mkForce "deadbeef";
    wireless.enable = false;
    enableIPv6 = true;
    useNetworkd = true;
    firewall = {
      enable = true;
      trustedInterfaces = [ "br0.lan" ];
    };
    nameservers = [ "192.168.23.5" ];
  };

  systemd.network =
    let
      bridgeName = "br0.lan";
    in
    {
      enable = true;
      # wait-online.anyInterface = true;
      netdevs = {
        "10-${bridgeName}" = {
          netdevConfig = {
            Kind = "bridge";
            Name = bridgeName;
          };
        };
      };
      networks = {
        "20-ixgbe" = {
          matchConfig.Driver = "ixgbe";
          networkConfig.Bridge = bridgeName;
          linkConfig.RequiredForOnline = "enslaved";
        };
        "20-gbe" = {
          matchConfig.Driver = "igb";
          networkConfig = {
            Bridge = bridgeName;
            ConfigureWithoutCarrier = true;
          };
          linkConfig.RequiredForOnline = "enslaved";
        };
        "10-${bridgeName}" = {
          matchConfig.Name = bridgeName;
          bridgeConfig = { };
          address = [
            "192.168.23.5/24"
          ];
          routes = [
            { Gateway = "192.168.23.1"; }
          ];
          networkConfig = {
            ConfigureWithoutCarrier = true;
            IPv6AcceptRA = true;
          };
          linkConfig.RequiredForOnline = "routable";
        };
      };
    };

  fileSystems."/" =
    {
      device = "spool/root/nixos";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-label/EFI";
      fsType = "vfat";
    };

  nix.settings.build-cores = lib.mkDefault 24;

  # deployment.keys."google-domain-owner-key" = {
  #   keyCommand = [ "pass" "google-domain-owner-key" ];
  #   destDir = "/run/keys";
  #   uploadAt = "pre-activation";
  # };

  # systemd.services.public-ip-sync-google-clouddns = {
  #   environment = {
  #     CLOUDSDK_CORE_PROJECT = "domain-owner";
  #     CLOUDSDK_COMPUTE_ZONE = "eu-west-1";
  #     GCLOUD_SERVICE_ACCOUNT_KEY_FILE = "/run/keys/google-domain-owner-key";
  #     GCLOUD_DNS_ZONE_ID = "satanic-link";
  #   };
  #   script = ''
  #     ${pkgs.public-ip-sync-google-clouddns}/bin/public-ip-sync-google-clouddns.sh -name "satanic.link."
  #   '';
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     Restart = "no";
  #   };
  # };

  # systemd.timers.public-ip-sync-google-clouddns = {
  #   partOf = [ "public-ip-sync-google-clouddns.service" ];
  #   wantedBy = [ "multi-user.target" ];
  #   timerConfig = {
  #     OnBootSec = "2min";
  #     OnUnitActiveSec = "3600";
  #   };
  # };
}
