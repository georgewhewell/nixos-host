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

  nixpkgs.config.permittedInsecurePackages = [
    "nodejs-16.20.2"
    "nodejs-16.20.1"
    "openssl-1.1.1w"
  ];

  imports =
    [
      ../../../containers/radarr.nix
      ../../../containers/sonarr.nix
      ../../../containers/unifi.nix

      ../../../profiles/common.nix
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
      ../../../services/jellyfin.nix
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
  boot.kernelPackages = pkgs.linuxPackages_lto_broadwell;

  boot.zfs.requestEncryptionCredentials = false;

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  fileSystems."/var/lib/lighthouse" =
    {
      device = "fpool/root/lighthouse-mainnet";
      fsType = "zfs";
      options = [ "nofail" "sync=disabled" ];
    };

  fileSystems."/var/lib/private/goethereum" =
    {
      device = "fpool/root/go-ethereum";
      fsType = "zfs";
      options = [ "nofail" "sync=disabled" ];
    };

  fileSystems."/var/lib/monero" =
    {
      device = "fpool/root/monero";
      fsType = "zfs";
      options = [ "nofail" "sync=disabled" ];
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
      address = "192.168.23.5";
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
    extraArgs = ''
      --checkpoint-sync-url=https://mainnet.checkpoint.sigp.io \
      --disable-deposit-contract-sync
    '';
  };

  services.geth =
    let
      apis = [ "net" "eth" "txpool" "debug" ];
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
    "reth-mainnet.satanic.link" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString 8549}";
      };
    };
    "reth-mainnet-ws.satanic.link" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString 8549}";
        proxyWebsockets = true;
      };
    };
  };

  services.monero = {
    enable = true;
    dataDir = "/var/lib/monero";
    rpc = {
      address = "192.168.23.5";
    };
    extraConfig = ''
      confirm-external-bind=1
    '';
  };


  # fileSystems."/mnt/nvraid" =
  #   {
  #     device = "/dev/md0";
  #     fsType = "f2fs";
  #     options = [ "nofail" "sync=disabled" ];
  #   };

  # virtualisation.oci-containers.containers.reth = {
  #   image = "ghcr.io/paradigmxyz/reth:v0.1.0-alpha.13";
  #   volumes = [
  #     "/mnt/nvraid/reth:/root/.local/share/reth"
  #     # re-use geth's jwt
  #     "/run/keys/LIGHTHOUSE_JWT:/root/.local/share/reth/mainnet/jwt.hex"
  #   ];
  #   cmd = [
  #     "node"
  #     "--full"
  #     "--authrpc.port=8552"
  #     "--port=30304"
  #     "--http"
  #     "--http.port=8549"
  #     "--metrics=9009"
  #     "--trusted-peers=enode://3c3a08e12a8686b204d2262bb5fdd7ec6babddb2542aa4f06ed951dbd1057ebf865d31d271837ce5fdd3de0c327b65c11eba2335c3bdbfab86cda963ecc18caa@192.18.23.5:30030"
  #   ];
  #   extraOptions = [ "--network=host" ];
  # };

  fileSystems."/var/lib/lighthouse-reth" =
    {
      device = "fpool/root/lighthouse-reth";
      fsType = "zfs";
      options = [ "nofail" "sync=disabled" ];
    };

  systemd.services.lighthouse-beacon-reth =
    let
      dataDir = "/var/lib/lighthouse-reth";
      network = "mainnet";
      port = 9002;
      address = "192.168.23.5";
      execution_address = "127.0.0.1";
      execution_port = 8552;
      http_address = "127.0.0.1";
      http_port = 8547;
      metrics_address = "127.0.0.1";
      metrics_port = 5055;
      jwtPath = "/run/keys/LIGHTHOUSE_JWT";
    in
    {
      description = "Lighthouse beacon node (connect to P2P nodes and verify blocks)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      script = ''
        # make sure the chain data directory is created on first run
        mkdir -p ${dataDir}/${network}

        ${pkgs.lighthouse}/bin/lighthouse beacon_node \
          --disable-upnp \
          --port ${toString port} \
          --listen-address ${address} \
          --network ${network} \
          --datadir ${dataDir}/${network} \
          --execution-endpoint http://${execution_address}:${toString execution_port} \
          --execution-jwt ''${CREDENTIALS_DIRECTORY}/LIGHTHOUSE_JWT \
          --http --http-address ${http_address} --http-port ${toString http_port} \
          --metrics --metrics-address ${metrics_address} --metrics-port ${toString metrics_port} \
          --checkpoint-sync-url="https://mainnet.checkpoint.sigp.io" \
          --libp2p-addresses "/ip4/192.168.23.5/tcp/9000" \
          --disable-deposit-contract-sync
      '';
      serviceConfig = {
        LoadCredential = "LIGHTHOUSE_JWT:${jwtPath}";
        DynamicUser = true;
        Restart = "on-failure";
        StateDirectory = "lighthouse-beacon";
        ReadWritePaths = [ dataDir ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectClock = true;
        ProtectProc = "noaccess";
        ProcSubset = "pid";
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RemoveIPC = true;
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
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

  networking = {
    hostName = "nixhost";
    hostId = lib.mkForce "deadbeef";
    wireless.enable = false;
    enableIPv6 = true;
    firewall = {
      enable = true;
      interfaces."br0.lan" = {
        allowedTCPPorts = [ 8085 9091 9000 9001 9002 18081 30030 30303 30304 38483 ];
        allowedUDPPorts = [ 9000 9001 9002 30030 30303 30304 ];
      };
    };
    defaultGateway = "192.168.23.1";
    nameservers = [ "192.168.23.1" ];
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
