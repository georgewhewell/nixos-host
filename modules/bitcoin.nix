{config, lib, pkgs, ...}:

with lib;

let
  cfg = config.services.bitcoin;
in
  {
    options.services.bitcoin = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable the BOINC distributed computing client. If this
          option is set to true, the bitcoin_client daemon will be run as a
          background service. The bitcoincmd command can be used to control the
          daemon.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.bitcoin;
        defaultText = "pkgs.bitcoin";
        description = ''
          Which BOINC package to use.
        '';
      };

      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/bitcoin";
        description = ''
          The directory in which to store BOINC's configuration and data files.
        '';
      };

      allowRemoteGuiRpc = mkOption {
        type = types.bool;
        default = false;
        description = ''
          If set to true, any remote host can connect to and control this BOINC
          client (subject to password authentication). If instead set to false,
          only the hosts listed in <varname>dataDir</varname>/remote_hosts.cfg will be allowed to
          connect.

          See also: <link xlink:href="http://bitcoin.berkeley.edu/wiki/Controlling_BOINC_remotely#Remote_access"/>
        '';
      };
    };

    config = mkIf cfg.enable {
      environment.systemPackages = [cfg.package];

      users.users.bitcoin = {
        createHome = false;
        description = "Bitcoin Client";
        home = cfg.dataDir;
        isSystemUser = true;
      };

      systemd.services.bitcoin = {
        description = "Bitcoind Client";
        after = ["network.target" "local-fs.target"];
        wantedBy = ["multi-user.target"];
        preStart = ''
          mkdir -p ${cfg.dataDir}
          chown bitcoin ${cfg.dataDir}
        '';
        script = ''
          ${cfg.package}/bin/bitcoind -datadir=${cfg.dataDir} -server -upnp -whitelist-rpc-ip=127.0.0.1 -alertnotify=echo -blocknotify=echo -rpcuser=moon -rpcpassword=moon -zmqpubrawtx=tcp://127.0.0.1:28332
        '';
        serviceConfig = {
          PermissionsStartOnly = true; # preStart must be run as root
          User = "bitcoin";
          Nice = 10;
        };
      };
    };
    meta = {};
  }
