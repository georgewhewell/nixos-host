{ config, lib, pkgs, ... }:

{

  fileSystems."/var/lib/besu" =
    {
      device = "fpool/root/besu";
      fsType = "zfs";
    };

  fileSystems."/var/lib/geth" =
    {
      device = "fpool/root/geth";
      fsType = "zfs";
    };

  /* services.geth-local = {
    enable = true;
    cacheSize = 1024 * 16;
  }; */

  # services.ipfs = {
  #   enable = true;
  #   gatewayAddress = "/ip4/127.0.0.1/tcp/58080";
  #   extraConfig = {
  #     Bootstrap = [
  #       "/ip4/128.199.219.111/tcp/4001/ipfs/QmSoLSafTMBsPKadTEgaXctDQVcqN88CNLHXMkTNwMKPnu"
  #       "/ip4/162.243.248.213/tcp/4001/ipfs/QmSoLueR4xBeUbY9WZ9xGUUxunbKWcrNFTDAadQJmocnWm"
  #     ];
  #   };
  # };

  # services.graph-node = {
  #   enable = true;
  #   ethereumRpc = "mainnet:https://mainnet.infura.io/v3/6205f86983d147e4b4e3e19aba591749";
  #   ipfs = "127.0.0.1:58080";
  #   postgresUrl = "postgres://graph-node:graph-node@localhost/graph-node";
  # };

  users.users.uniswap = {
    group = "uniswap";
    description = "uniswap";
    home = "/var/lib/uniswap/";
    createHome = true;
    isNormalUser = true;
  };

  users.groups.uniswap = {
    name = "uniswap";
  };

  systemd.services.uniswap = let
    cmdArgs = [ "uniswap" "watch" ];
  in {
    description = "uniswap Service";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network-online.target" ];

    environment = {
      RUST_LOG = "info";
      RUST_BACKTRACE = "1";
      ETH_URL = "ws://192.168.25.2:8546";
      BSC_ETH_URL = "ws://192.168.25.2:8576";
      DATABASE_URL = "postgres://swaps:swaps@127.0.0.1/swaps3";
    };

    script = ''
      ${pkgs.uniswap}/bin/uniswap-data uniswap load-tokens
      ${pkgs.uniswap}/bin/uniswap-data uniswap load-pairs
      ${pkgs.uniswap}/bin/uniswap-data uniswap ${lib.escapeShellArgs cmdArgs}
    '';

    startLimitIntervalSec = 5;
    startLimitBurst = 1;

    serviceConfig = {
      User = "uniswap";
      Group = "uniswap";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

}
