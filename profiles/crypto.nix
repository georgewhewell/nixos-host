{ config, lib, pkgs, inputs, ... }:

let
  dataRoot = "/mnt/nvraid";
  lanAddr = "192.168.23.5";
in
{
  imports = [ inputs.nix-bitcoin.nixosModules.default ];

  #nvraid
  fileSystems.${dataRoot} =
    {
      device = "/dev/md0";
      fsType = "xfs";
      options = [ "nofail" "sync=disabled" ];
    };

  # radicle
  services.radicle = {
    enable = true;
    listen = "127.0.0.1:8089";
  };

  # monero
  fileSystems."/var/lib/monero" =
    {
      device = "fpool/root/monero";
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
  nix-bitcoin = {
    generateSecrets = true;
    secretsDir = "${dataRoot}/bitcoind";
  };

  services.bitcoind = {
    enable = true;
    dataDir = "${dataRoot}/bitcoind";
    # listen = "${lanAddr}:8333";
    disablewallet = true;
    rpc = {
      address = lanAddr;
    };
  };

  networking.firewall.allowedTCPPorts = [ 8333 ];
  networking.firewall.allowedUDPPorts = [ 8333 ];

  # ethereum
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

}
