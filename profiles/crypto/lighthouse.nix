{
  config,
  lib,
  pkgs,
  inputs,
  mkSecret,
  network,
  ...
}: let
  trexIp = network.primaryIp network.hosts.trex;
in {
  imports = [inputs.ethereum.nixosModules.default];

  sops.secrets.lighthouse-jwt = mkSecret "lighthouse-jwt" {};

  fileSystems."/var/lib/private/lighthouse-mainnet" = {
    device = "pool3d/root/ethereum/lighthouse-mainnet";
    fsType = "zfs";
    options = ["nofail" "sync=disabled"];
  };

  fileSystems."/var/lib/private/reth-mainnet" = {
    device = "pool3d/root/ethereum/reth-mainnet";
    fsType = "zfs";
    options = ["nofail" "sync=disabled"];
  };

  services.ethereum.lighthouse-beacon.mainnet = {
    enable = true;
    args = {
      network = "mainnet";
      datadir = "/var/lib/lighthouse-mainnet";
      execution-endpoint = "http://127.0.0.1:8551";
      execution-jwt = config.sops.secrets.lighthouse-jwt.path;
      checkpoint-sync-url = "https://beaconstate.info";
      discovery-port = 9000;
      metrics = {
        enable = true;
        address = "0.0.0.0";
        port = 5054;
      };
      http = {
        enable = true;
        address = trexIp;
        port = 5052;
      };
    };
    openFirewall = true;
  };

  services.ethereum.reth.mainnet = {
    enable = true;
    args = {
      datadir = "/var/lib/reth-mainnet";
      port = 30303;
      chain = "mainnet";
      authrpc = {
        addr = "127.0.0.1";
        port = 8551;
        jwtsecret = config.sops.secrets.lighthouse-jwt.path;
      };
      http = {
        enable = true;
        addr = "127.0.0.1";
        port = 8545;
        api = ["eth" "net" "web3"];
      };
      ws = {
        enable = true;
        addr = "127.0.0.1";
        port = 8546;
        api = ["eth" "net" "web3"];
      };
      metrics = {
        enable = true;
        addr = "0.0.0.0";
        port = 6060;
      };
    };
    openFirewall = true;
  };

  networking.firewall.allowedTCPPorts = [5054 6060];

  systemd.services.lighthouse-beacon-mainnet = {
    unitConfig.RequiresMountsFor = ["/var/lib/private/lighthouse-mainnet"];
    after = ["sops-nix.service"];
  };

  systemd.services.reth-mainnet = {
    unitConfig.RequiresMountsFor = ["/var/lib/private/reth-mainnet"];
    # ethereum.nix module bug: generates args twice with both . and - separators
    # Override ExecStart to only use the correct . separator format
    serviceConfig.ExecStart = let
      reth = "${pkgs.reth}/bin/reth";
      jwt = "%d/jwtsecret";
    in
      lib.mkForce ''
        ${reth} node \
          --log.file.directory /var/lib/reth-mainnet/logs \
          --datadir /var/lib/reth-mainnet \
          --authrpc.jwtsecret ${jwt} \
          --authrpc.addr 127.0.0.1 \
          --authrpc.port 8551 \
          --chain mainnet \
          --port 30303 \
          --http \
          --http.addr 127.0.0.1 \
          --http.port 8545 \
          --http.api eth,net,web3 \
          --ws \
          --ws.addr 127.0.0.1 \
          --ws.port 8546 \
          --ws.api eth,net,web3 \
          --metrics 0.0.0.0:6060
      '';
  };
}
