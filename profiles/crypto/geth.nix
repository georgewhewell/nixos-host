{ config, lib, pkgs, inputs, ... }:

{

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

  systemd.services.lighthouse-beacon.unitConfig = {
    RequiresMountsFor = [ config.services.lighthouse.beacon.dataDir ];
    ConditionPathExists = config.services.lighthouse.beacon.execution.jwtPath;
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

  systemd.services.geth-mainnet.unitConfig = {
    RequiresMountsFor = [ "/var/lib/private/goethereum" ];
    ConditionPathExists = config.services.geth.mainnet.authrpc.jwtsecret;
  };

}
