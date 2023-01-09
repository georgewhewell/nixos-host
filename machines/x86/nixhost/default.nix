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

  deployment.targetHost = "192.168.23.1";

  imports =
    [
      ../../../containers/radarr.nix
      ../../../containers/sonarr.nix
      ../../../containers/unifi.nix

      ../../../profiles/bridge-interfaces.nix
      ../../../profiles/common.nix
      #    ../../../profiles/development.nix
      ../../../profiles/headless.nix
      ../../../profiles/home.nix
      ../../../profiles/logserver.nix
      ../../../profiles/nas.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/router.nix
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

  boot.kernelPackages = pkgs.linuxPackages_latest_lto_broadwell;
  boot.zfs.requestEncryptionCredentials = false;
  # boot.kernelPackages = pkgs.linuxPackages_latest;

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };


  fileSystems."/var/lib/lighthouse" =
    {
      device = "fpool/root/lighthouse-mainnet";
      fsType = "zfs";
      options = [ "nofail" ];
    };

  deployment.keys =
    {
      "LIGHTHOUSE_JWT" = {
        keyCommand = [ "pass" "erigon-gpg" ];
        destDir = "/run/keys";
        uploadAt = "pre-activation";
      };
    };

  services.lighthouse = {
    beacon = {
      enable = true;
      dataDir = "/var/lib/lighthouse";
      execution = {
        address = "127.0.0.1";
        port = 8551;
        jwtPath = "/run/keys/LIGHTHOUSE_JWT";
      };
      metrics = {
        enable = true;
        port = 5054;
      };
    };
    extraArgs = ''--checkpoint-sync-url="https://mainnet.checkpoint.sigp.io"'';
  };



  fileSystems."/var/lib/private/goethereum" =
    {
      device = "fpool/root/go-ethereum";
      fsType = "zfs";
      options = [ "nofail" ];
    };

  services.geth =
    let
      apis = [ "net" "eth" "txpool" ];
      mainnet = {
        metrics = 6060;
        p2p = 30030;
        http = 8545;
        ws = 8546;
      };
    in
    {
      mainnet = with mainnet; {
        enable = true;
        maxpeers = 128;
        syncmode = "snap";
        gcmode = "full";
        metrics = {
          enable = true;
          address = "0.0.0.0";
          port = metrics;
        };
        port = p2p;
        http = {
          enable = true;
          port = http;
          address = "0.0.0.0"; # firewalled
          inherit apis;
        };
        websocket = {
          enable = true;
          port = ws;
          address = "0.0.0.0"; # firewalled
          inherit apis;
        };
        authrpc = {
          enable = true;
          address = "localhost";
          port = 8551;
        };
        extraArgs = [
          "--cache=16000"
          "--http.vhosts=eth-mainnet.satanic.link,eth-mainnet-ws.satanic.link,localhost,127.0.0.1"
        ];
      };
    };

  services.nginx.virtualHosts = {
    "eth-mainnet.satanic.link" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString config.services.geth.mainnet.http.port}";
      };
    };

    "eth-mainnet-ws.satanic.link" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString config.services.geth.mainnet.websocket.port}";
        proxyWebsockets = true;
      };
    };
  };

  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
  ];

  boot.supportedFilesystems = [ "zfs" ];
  boot.binfmt.emulatedSystems = [ "aarch64-linux" "armv7l-linux" ];
  boot.kernelParams = [
    # https://bugzilla.kernel.org/show_bug.cgi?id=203475#c61
    "libata.force=5:3.0Gbps"
    "libata.force=6:3.0Gbps"
    "libata.force=5:noncq,noncqtrim"
    "libata.force=6:noncq,noncqtrim"

    # optane zil/l2arc
    "zfs.zfs_immediate_write_sz=${toString (128 * 1024 * 1024)}"
    "zfs.l2arc_feed_min_ms=15"
    "zfs.l2arc_nopreFfetch=1"
    "zfs.l2arc_write_boost=${toString (2 * 1024 * 1024 * 1024)}"
    "zfs.l2arc_write_max=${toString (2 * 1024 * 1024 * 1024)}"
    "zfs.zfs_arc_max=12884901888"
  ];

  networking = {
    hostName = "nixhost";
    hostId = lib.mkForce "deadbeef";
    firewall = {
      checkReversePath = false;
    };
  };

  fileSystems."/" =
    {
      device = "/dev/mapper/vg1-nixos";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-label/EFI";
      fsType = "vfat";
    };

  nix.settings.build-cores = lib.mkDefault 24;

}
