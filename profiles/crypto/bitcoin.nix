{
  config,
  lib,
  inputs,
  ...
}: {
  imports = [inputs.nix-bitcoin.nixosModules.default];

  # bitcoind
  fileSystems."/var/lib/bitcoind" = {
    device = "pool3d/root/bitcoind";
    fsType = "zfs";
    options = ["nofail" "sync=disabled"];
  };

  systemd.services.bitcoind = {
    unitConfig.RequiresMountsFor = [config.services.bitcoind.dataDir];
    # Add these to help with permissions and startup
    serviceConfig = {
      StateDirectory = "bitcoind";
      RuntimeDirectory = "bitcoind";
      RuntimeDirectoryMode = "0750";
    };
  };

  # chown bitcoind data dir
  nix-bitcoin = {
    generateSecrets = true;
    secretsDir = "/var/lib/bitcoind";
  };

  services.bitcoind = {
    enable = true;
    listen = true;
    address = "0.0.0.0";
    port = 8333;
    dataDir = "/var/lib/bitcoind";
    # dataDirReadableByGroup = true;
    disablewallet = true;
    # Add these basic settings
    extraConfig = ''
      dbcache=450
      maxconnections=40
      maxuploadtarget=5000
    '';
    rpc = {
      users = lib.mkForce {};
      # address = lanAddr;
    };
  };

  networking.firewall = {
    allowedTCPPorts = [config.services.bitcoind.port];
    allowedUDPPorts = [config.services.bitcoind.port];
  };
}
