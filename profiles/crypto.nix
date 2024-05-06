{ config, lib, pkgs, inputs, ... }:

let
  lanAddr = "192.168.23.5";
in
{
  imports = [ inputs.nix-bitcoin.nixosModules.default ];

  # radicle
  services.radicle = {
    enable = false;
    listen = "127.0.0.1:8089";
  };

  # monero
  fileSystems."/var/lib/monero" =
    {
      device = "nvpool/root/monero";
      fsType = "zfs";
      options = [ "nofail" "sync=disabled" ];
    };

  services.monero = {
    enable = true;
    dataDir = "/var/lib/monero";
    rpc = {
      address = lanAddr;
    };
    extraConfig = ''
      confirm-external-bind=1
    '';
  };

  # bitcoind
  fileSystems."/var/lib/bitcoind" =
    {
      device = "nvpool/root/bitcoind";
      fsType = "zfs";
      options = [ "nofail" "sync=disabled" ];
    };

  nix-bitcoin = {
    generateSecrets = true;
    secretsDir = "/var/lib/bitcoind";
  };

  services.bitcoind = {
    enable = true;
    dataDir = "/var/lib/bitcoind";
    disablewallet = true;
    rpc = {
      users = lib.mkForce { };
      # address = lanAddr;
    };
  };

  networking.firewall.allowedTCPPorts = [ 8333 9000 ];
  networking.firewall.allowedUDPPorts = [ 8333 9000 ];

  # ethereum
  fileSystems."/var/lib/lighthouse" =
    {
      device = "nvpool/root/ethereum/lighthouse-geth-mainnet";
      fsType = "zfs";
      options = [ "nofail" "sync=disabled" ];
    };

  fileSystems."/var/lib/private/goethereum" =
    {
      device = "nvpool/root/ethereum/geth-mainnet";
      fsType = "zfs";
      options = [ "nofail" "sync=disabled" ];
    };

  deployment.keys = {
    "LIGHTHOUSE_JWT" = {
      keyCommand = [ "pass" "erigon-gpg" ];
      destDir = "/run/keys";
      uploadAt = "pre-activation";
    };
    "LIGHTHOUSE_JWT_GETH" = {
      keyCommand = [ "pass" "erigon-gpg" ];
      destDir = "/var/lib/goethereum/mainnet";
      uploadAt = "pre-activation";
      permissions = "0444";
    };
  };

  # use lighthouse from nix-ethereum
  nixpkgs.overlays = [
    (self: _: {
      geth = inputs.ethereum.packages.${pkgs.system}.geth;
      lighthouse = inputs.ethereum.packages.${pkgs.system}.lighthouse;
    })
  ];

  services.lighthouse = {
    beacon = {
      enable = true;
      dataDir = "/var/lib/lighthouse";
      address = lanAddr;
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
        package = inputs.ethereum.packages.${pkgs.system}.geth;
        maxpeers = 128;
        syncmode = "snap";
        gcmode = "archive";
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
          jwtsecret = "/var/lib/goethereum/mainnet/LIGHTHOUSE_JWT_GETH";
        };
        extraArgs = [
          "--cache=16000"
          "--http.vhosts=eth-mainnet.satanic.link,eth-mainnet-ws.satanic.link,localhost,127.0.0.1"
        ];
      };
    };

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

  # fileSystems."/var/lib/lighthouse-reth" =
  #   {
  #     device = "fpool/root/lighthouse-reth";
  #     fsType = "zfs";
  #     options = [ "nofail" "sync=disabled" ];
  #   };

  # systemd.services.lighthouse-beacon-reth =
  #   let
  #     dataDir = "/var/lib/lighthouse-reth";
  #     network = "mainnet";
  #     port = 9002;
  #     address = "192.168.23.5";
  #     execution_address = "127.0.0.1";
  #     execution_port = 8552;
  #     http_address = "127.0.0.1";
  #     http_port = 8547;
  #     metrics_address = "127.0.0.1";
  #     metrics_port = 5055;
  #     jwtPath = "/run/keys/LIGHTHOUSE_JWT";
  #   in
  #   {
  #     description = "Lighthouse beacon node (connect to P2P nodes and verify blocks)";
  #     wantedBy = [ "multi-user.target" ];
  #     after = [ "network.target" ];
  #     script = ''
  #       # make sure the chain data directory is created on first run
  #       mkdir -p ${dataDir}/${network}

  #       ${pkgs.lighthouse}/bin/lighthouse beacon_node \
  #         --disable-upnp \
  #         --port ${toString port} \
  #         --listen-address ${address} \
  #         --network ${network} \
  #         --datadir ${dataDir}/${network} \
  #         --execution-endpoint http://${execution_address}:${toString execution_port} \
  #         --execution-jwt ''${CREDENTIALS_DIRECTORY}/LIGHTHOUSE_JWT \
  #         --http --http-address ${http_address} --http-port ${toString http_port} \
  #         --metrics --metrics-address ${metrics_address} --metrics-port ${toString metrics_port} \
  #         --checkpoint-sync-url="https://mainnet.checkpoint.sigp.io" \
  #         --libp2p-addresses "/ip4/192.168.23.5/tcp/9000" \
  #         --disable-deposit-contract-sync
  #     '';
  #     serviceConfig = {
  #       LoadCredential = "LIGHTHOUSE_JWT:${jwtPath}";
  #       DynamicUser = true;
  #       Restart = "on-failure";
  #       StateDirectory = "lighthouse-beacon";
  #       ReadWritePaths = [ dataDir ];
  #       NoNewPrivileges = true;
  #       PrivateTmp = true;
  #       ProtectHome = true;
  #       ProtectClock = true;
  #       ProtectProc = "noaccess";
  #       ProcSubset = "pid";
  #       ProtectKernelLogs = true;
  #       ProtectKernelModules = true;
  #       ProtectKernelTunables = true;
  #       ProtectControlGroups = true;
  #       ProtectHostname = true;
  #       RestrictSUIDSGID = true;
  #       RestrictRealtime = true;
  #       RestrictNamespaces = true;
  #       LockPersonality = true;
  #       RemoveIPC = true;
  #       SystemCallFilter = [ "@system-service" "~@privileged" ];
  #     };
  #   };

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

}
