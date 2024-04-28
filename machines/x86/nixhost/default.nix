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

  deployment.targetHost = "192.168.23.5";
  deployment.targetUser = "grw";

  imports =
    [
      ../../../containers/radarr.nix
      ../../../containers/sonarr.nix
      ../../../containers/gh-runner.nix

      # ../../../containers/unifi.nix

      ../../../profiles/common.nix
      ../../../profiles/crypto.nix
      ../../../profiles/headless.nix
      ../../../profiles/home.nix
      ../../../profiles/logserver.nix
      ../../../profiles/nas.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/fastlan.nix

      ../../../services/buildfarm-slave.nix
      ../../../services/docker.nix
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
    };

    relay = {
      enable = true;
      role = "bridge";
    };

    settings = {
      ORPort = 9999;
    };
  };

  # boot.zfs.enableUnstable = true;
  # boot.kernelPackages = pkgs.linuxPackages_lto_broadwell;
  # boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

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
        domain=lan
        bind-interfaces
        interface=${lanBridge}
        dhcp-range=${lanBridge},192.168.23.10,192.168.23.249,6h
        dhcp-option=${lanBridge},3,192.168.23.1    # send default gateway
        dhcp-host=e4:8d:8c:a8:de:40,192.168.23.2   # switch
        dhcp-host=80:2a:a8:80:96:ef,192.168.23.3   # ap
        dhcp-host=0c:c4:7a:89:fb:37,192.168.23.4   # ipmi
        dhcp-host=0c:c4:7a:87:b9:d8,192.168.23.5   # nixhost
        dhcp-host=78:11:dc:ec:86:ea,192.168.23.6   # vacuum
        dhcp-host=06:f1:3e:03:27:8c,192.168.23.7   # fuckup
        dhcp-host=50:6b:4b:03:04:cb,192.168.23.8   # trex
        dhcp-host=c2:be:3b:97:be:27,192.168.23.48  # phone

        # hosted names
        address=/router.lan/192.168.23.1
        address=/nixhost.lan/192.168.23.5
        address=/fuckup.lan/192.168.23.7
        address=/trex.lan/192.168.23.8
        address=/cloud.lan/192.168.24.2
        address=/satanic.link/192.168.23.254
        address=/grafana.satanic.link/192.168.23.5
        address=/home.satanic.link/192.168.23.5
        address=/jellyfin.satanic.link/192.168.23.254
        address=/paperless.satanic.link/192.168.23.5
        address=/radarr.satanic.link/192.168.23.5
        address=/sonarr.satanic.link/192.168.23.5
        address=/eth-mainnet.satanic.link/192.168.23.5
        address=/eth-mainnet-ws.satanic.link/192.168.23.5
      '';
    };

  networking = {
    hostName = "nixhost";
    hostId = lib.mkForce "deadbeef";
    wireless.enable = false;
    enableIPv6 = true;
    firewall = {
      enable = true;
      trustedInterfaces = [ "br0.lan" ];
      interfaces."br0.lan" = {
        allowedTCPPorts = [ 8085 9091 9000 9001 9002 18081 30030 30303 30304 38483 18080 17026 ];
        allowedUDPPorts = [ 9000 9001 9002 30030 30303 30304 18080 17026 ];
      };
    };
    defaultGateway = "192.168.23.1";
    nameservers = [ "192.168.23.5" ];
    interfaces."br0.lan" = {
      useDHCP = false;
      ipv4.addresses = [{
        address = "192.168.23.5";
        prefixLength = 24;
      }];
    };

    bridges."br0.lan" = {
      interfaces = [
        "eno1"
        "eno2"
        "eno3"
        "eno4"
      ];
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

}
