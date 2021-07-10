{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.ethminer-proxychain;
  poolUrl = escapeShellArg "stratum1+ssl://${cfg.wallet}.${cfg.rig}@${cfg.pool}:${toString cfg.stratumPort}";
in

{

  ###### interface

  options = {

    services.ethminer-proxychain = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable ethminer ether mining.";
      };

      proxyChain = mkOption {
        type = types.str;
        default = null;
      };

      recheckInterval = mkOption {
        type = types.int;
        default = 2000;
        description = "Interval in milliseconds between farm rechecks.";
      };

      toolkit = mkOption {
        type = types.enum [ "cuda" "opencl" ];
        default = "cuda";
        description = "Cuda or opencl toolkit.";
      };

      apiPort = mkOption {
        type = types.int;
        default = -3333;
        description = "Ethminer api port. minus sign puts api in read-only mode.";
      };

      wallet = mkOption {
        type = types.str;
        example = "0x0123456789abcdef0123456789abcdef01234567";
        description = "Ethereum wallet address.";
      };

      pool = mkOption {
        type = types.str;
        example = "eth-us-east1.nanopool.org";
        description = "Mining pool address.";
      };

      stratumPort = mkOption {
        type = types.port;
        default = 9999;
        description = "Stratum protocol tcp port.";
      };

      rig = mkOption {
        type = types.str;
        default = "mining-rig-name";
        description = "Mining rig name.";
      };

      registerMail = mkOption {
        type = types.str;
        example = "email%40example.org";
        description = "Url encoded email address to register with pool.";
      };

      maxPower = mkOption {
        type = types.int;
        default = 113;
        description = "Miner max watt usage.";
      };

    };

  };


  ###### implementation

  config = mkIf cfg.enable {

    systemd.services.ethminer = {
      description = "ethminer ethereum mining service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        DynamicUser = true;
        ExecStartPre = "${pkgs.ethminer}/bin/.ethminer-wrapped --list-devices";
        Restart = "always";
      };

      script = let
        proxychainConfig = pkgs.writeText "proxychain.cnf" ''
          [ProxyList]
          ${cfg.proxyChain}
        '';
      in ''
        ${pkgs.ethminer}/bin/.ethminer-wrapped \
          --farm-recheck ${toString cfg.recheckInterval} \
          --report-hashrate \
          --${cfg.toolkit} \
          --api-port ${toString cfg.apiPort} \
          --pool ${poolUrl}
      '';

    };

  };

}
