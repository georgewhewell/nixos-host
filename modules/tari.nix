{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.tari;
in {
  options.services.tari = {
    enable = mkEnableOption "Tari base node";

    dataDir = mkOption {
      type = types.path;
      default = "/pool3d/root/tari";
      description = "Directory to store Tari node data";
    };

    network = mkOption {
      type = types.enum ["mainnet" "stagenet" "nextnet" "localnet"];
      default = "mainnet";
      description = "Network to connect to";
    };

    port = mkOption {
      type = types.port;
      default = 18189;
      description = "Port for peer connections";
    };

    grpcPort = mkOption {
      type = types.port;
      default = 18142;
      description = "Port for gRPC connections";
    };

    walletPort = mkOption {
      type = types.port;
      default = 18143;
      description = "Port for gRPC connections";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall ports for Tari node";
    };

    image = mkOption {
      type = types.str;
      default = "quay.io/tarilabs/minotari_node:latest-mainnet";
      description = "Docker image to use for Tari node";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra command line arguments to pass to minotari_node";
    };
  };

  config = let
    lanIp = "192.168.23.8";
  in
    mkIf cfg.enable {
      virtualisation = {
        podman = {
          enable = true;
          defaultNetwork.settings.dns_enabled = true;
        };
      };

      systemd.tmpfiles.rules = [
        "d '${cfg.dataDir}' 0755 root root - -"
      ];

      virtualisation.oci-containers = {
        backend = "podman";
        containers.tari = {
          image = cfg.image;
          volumes = [
            "${cfg.dataDir}:/var/tari"
          ];
          environment = {
            TARI_NODE_CREATE_ID = "true";
          };
          cmd =
            [
              "--network"
              cfg.network
              "--non-interactive"
            ]
            ++ cfg.extraArgs;
          extraOptions = [
            "--network=bridge"
            "-p"
            "${lanIp}:${toString cfg.port}:${toString cfg.port}"
            "-p"
            "${lanIp}:${toString cfg.grpcPort}:${toString cfg.grpcPort}"
            "-p"
            "${lanIp}:${toString cfg.walletPort}:${toString cfg.walletPort}"
          ];
          autoStart = true;
        };
      };

      systemd.services.podman-tari.unitConfig.RequiresMountsFor = [cfg.dataDir];

      networking.firewall = mkIf (cfg.openFirewall && config.networking.firewall.enable) {
        allowedTCPPorts = [cfg.grpcPort cfg.walletPort];
      };
    };
}
