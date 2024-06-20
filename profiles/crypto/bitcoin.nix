{ config, pkgs, lib, inputs, ... }:

{
  imports = [ inputs.nix-bitcoin.nixosModules.default ];

  # bitcoind
  fileSystems."/var/lib/bitcoind" =
    {
      device = "nvpool/root/bitcoind";
      fsType = "zfs";
      options = [ "nofail" "sync=disabled" ];
    };

  systemd.services.bitcoind.unitConfig.RequiresMountsFor = [ config.services.bitcoind.dataDir ];

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
}
