{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  # ethereum
  fileSystems."/var/lib/lighthouse" = {
    device = "pool3d/root/ethereum/lighthouse-geth-mainnet";
    fsType = "zfs";
    options = ["nofail" "sync=disabled"];
  };

  # fileSystems."/var/lib/private/goethereum" = {
  #   device = "nvpool/root/ethereum/geth-mainnet";
  #   fsType = "zfs";
  #   options = ["nofail" "sync=disabled"];
  # };

  deployment.keys = {
    "LIGHTHOUSE_JWT" = {
      keyCommand = ["pass" "erigon-gpg"];
      destDir = "/run/keys";
      uploadAt = "pre-activation";
    };
    # "LIGHTHOUSE_JWT_GETH" = {
    #   keyCommand = ["pass" "erigon-gpg"];
    #   destDir = "/var/lib/goethereum/mainnet";
    #   uploadAt = "pre-activation";
    #   permissions = "0444";
    # };
  };

  # imports = [inputs.ethereum.nixosModules.default];

  # use lighthouse from nix-ethereum
  nixpkgs.overlays = [
    (self: _: {
      geth = inputs.ethereum.packages.${pkgs.system}.geth;
      lighthouse = inputs.ethereum.packages.${pkgs.system}.lighthouse;
      reth = inputs.ethereum.packages.${pkgs.system}.reth;
    })
  ];

  services.lighthouse = {
    beacon = {
      enable = true;
      dataDir = "/var/lib/lighthouse";
      address = "192.168.23.8";
      execution = {
        address = "127.0.0.1";
        port = 8551;
        jwtPath = "/run/keys/LIGHTHOUSE_JWT";
      };
      metrics = {
        enable = true;
        address = "0.0.0.0";
        port = 5054;
      };
    };
    extraArgs = ''
      --checkpoint-sync-url=https://mainnet.checkpoint.sigp.io \
      --disable-deposit-contract-sync
    '';
  };

  networking.firewall.allowedTCPPorts = [9000 6060 5054 30303];
  networking.firewall.allowedUDPPorts = [9000 9001 30303];

  systemd.services.lighthouse-beacon.unitConfig = {
    RequiresMountsFor = [config.services.lighthouse.beacon.dataDir];
    ConditionPathExists = config.services.lighthouse.beacon.execution.jwtPath;
  };

  services.reth.mainnet = {
    enable = true;
    args = {
      datadir = "/var/lib/reth"; # You'll need to create a ZFS dataset for this

      # Network settings
      port = 30303;
      chain = "mainnet";

      # HTTP RPC settings
      http = {
        enable = true;
        addr = "127.0.0.1";
        port = 8545;
      };

      # WebSocket settings
      ws = {
        enable = true;
        addr = "127.0.0.1";
        port = 8546;
      };

      # Engine API settings (for Lighthouse connection)
      authrpc = {
        addr = "127.0.0.1";
        port = 8551;
        jwtsecret = "/run/keys/LIGHTHOUSE_JWT"; # Use the same JWT as Lighthouse
      };

      # Metrics (matching your previous setup)
      metrics = {
        enable = true;
        addr = "0.0.0.0";
        port = 6060;
      };
    };
  };

  # Add ZFS mount for Reth
  fileSystems."/var/lib/reth" = {
    device = "pool3d/root/ethereum/reth-mainnet"; # Adjust pool name as needed
    fsType = "zfs";
    options = ["nofail" "sync=disabled"];
  };

  # Add systemd dependencies
  systemd.services.reth = {
    unitConfig = {
      RequiresMountsFor = ["/var/lib/reth"];
      ConditionPathExists = config.services.reth.authrpc.jwtsecret;
    };
  };
}
