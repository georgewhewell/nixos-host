{ config, lib, pkgs, ... }:
let
  cfg = config.sconfig.optimism;
in
{

  options.sconfig.optimism = {
    enable = lib.mkEnableOption "Optimism node";
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/optimism";
      description = ''
        data root
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # users.optimism = { };

    systemd.services.optimism-create-dirs = {
      description = "create optimism data dirs";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.bash}/bin/bash -c 'mkdir -p /var/lib/optimism/{db,geth}'";
        # User = cfg.user;
        # Group = cfg.group;
      };
    };

    virtualisation.oci-containers.containers = {
      optimism-dtl = {
        image = "ethereumoptimism/data-transport-layer";
        environment = {
          DATA_TRANSPORT_LAYER__ADDRESS_MANAGER = "0xdE1FCfB0851916CA5101820A69b13a4E276bd81F";
          DATA_TRANSPORT_LAYER__SYNC_FROM_L1 = "true";
          DATA_TRANSPORT_LAYER__SYNC_FROM_L2 = "false";
          DATA_TRANSPORT_LAYER__L1_START_HEIGHT = "13596466";
          DATA_TRANSPORT_LAYER__CONFIRMATIONS = "12";
          DATA_TRANSPORT_LAYER__DANGEROUSLY_CATCH_ALL_ERRORS = "true";
          DATA_TRANSPORT_LAYER__DB_PATH = "/db";
          DATA_TRANSPORT_LAYER__DEFAULT_BACKEND = "l1";
          DATA_TRANSPORT_LAYER__L1_GAS_PRICE_BACKEND = "l1";
          DATA_TRANSPORT_LAYER__L1_RPC_ENDPOINT = "https://eth-mainnet.satanic.link";
          DATA_TRANSPORT_LAYER__ENABLE_METRICS = "true";
          DATA_TRANSPORT_LAYER__ETH_NETWORK_NAME = "mainnet";
          DATA_TRANSPORT_LAYER__L2_CHAIN_ID = "10";
          DATA_TRANSPORT_LAYER__LOGS_PER_POLLING_INTERVAL = "2000";
          DATA_TRANSPORT_LAYER__NODE_ENV = "production";
          DATA_TRANSPORT_LAYER__POLLING_INTERVAL = "500";
          DATA_TRANSPORT_LAYER__SENTRY_TRACE_RATE = "0.05";
          DATA_TRANSPORT_LAYER__SERVER_HOSTNAME = "0.0.0.0";
          DATA_TRANSPORT_LAYER__SERVER_PORT = "7878";
          DATA_TRANSPORT_LAYER__TRANSACTIONS_PER_POLLING_INTERVAL = "1000";
        };
        ports = [ "7878:7878" ];
        volumes = [
          "${cfg.dataDir}/dtl:/db"
        ];
      };
      optimism-l2geth = {
        image = "ethereumoptimism/l2geth";
        environment = {
          USING_OVM = "true";
          SEQUENCER_CLIENT_HTTP = "https://mainnet.optimism.io";
          BLOCK_SIGNER_ADDRESS = "0x00000398232E2064F896018496b4b44b3D62751F";
          BLOCK_SIGNER_PRIVATE_KEY = "";
          BLOCK_SIGNER_PRIVATE_KEY_PASSWORD = "pwd";
          ETH1_CTC_DEPLOYMENT_HEIGHT = "13596466";
          ETH1_SYNC_SERVICE_ENABLE = "true";
          L2GETH_GENESIS_URL = "https://storage.googleapis.com/optimism/mainnet/genesis-berlin.json";
          L2GETH_GENESIS_HASH = "0x106b0a3247ca54714381b1109e82cc6b7e32fd79ae56fbcc2e7b1541122f84ea";
          L2GETH_BERLIN_ACTIVATION_HEIGHT = "3950000";
          ROLLUP_BACKEND = "l1";
          ROLLUP_CLIENT_HTTP = "http://optimism-dtl:7878";
          ROLLUP_DISABLE_TRANSFERS = "false";
          ROLLUP_ENABLE_L2_GAS_POLLING = "false";
          ROLLUP_GAS_PRICE_ORACLE_OWNER_ADDRESS = "0x648E3e8101BFaB7bf5997Bd007Fb473786019159";
          ROLLUP_MAX_CALLDATA_SIZE = "40000";
          ROLLUP_POLL_INTERVAL_FLAG = "1s";
          ROLLUP_SYNC_SERVICE_ENABLE = "true";
          ROLLUP_TIMESTAMP_REFRESH = "5m";
          ROLLUP_VERIFIER_ENABLE = "true";
        };
        ports = [ "9991:8545" "9992:8546" ];
        volumes = [
          "${cfg.dataDir}/geth:/geth"
        ];
      };
    };
  };
}
