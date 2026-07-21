{
  config,
  lib,
  mkSecret,
  network,
  pkgs,
  ...
}: let
  cfg = config.sconfig.mounts.beegfs;
  mgmtdHost = network.ipOf "fabric" network.hosts.bluefield2.addresses.fabric;
  clientInterfaces = pkgs.writeText
    "beegfs-client-interfaces-${config.networking.hostName}"
    (lib.concatMapStrings (address: "* ${address} 4\n") cfg.clientAddresses);
in {
  options.sconfig.mounts.beegfs = {
    enable = lib.mkEnableOption "the shared failure-tolerant BeeGFS mount";

    clientAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "192.168.25.101" ];
      description = ''
        Local IPv4 addresses the BeeGFS client advertises to peers, in
        priority order. Addresses not listed here are not advertised.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.clientAddresses != [ ];
        message = "sconfig.mounts.beegfs.clientAddresses must contain at least one address";
      }
    ];

    services.beegfs-cluster = {
      inherit mgmtdHost;
      connAuthFile = config.sops.secrets.beegfs-conn-auth.path;
      rdma = true;
      client = {
        enable = true;
        mounts."/mnt/beegfs" = {
          # Boot installs only the autofs trigger. Contact with the BeeGFS
          # cluster is deferred until something actually accesses the path.
          automount = true;
          idleTimeoutSec = "10min";
          mountTimeoutSec = "15s";
          settings = {
            connInterfacesFile = "${clientInterfaces}";
            # The cluster root uses 4 MiB stripes.  BeeGFS recommends at
            # least one full chunk of RDMA buffers per connection; the
            # 8 KiB x 70 defaults provide only 560 KiB and split every
            # sequential chunk into several request/response rounds.
            connRDMABufSize = 131072;
            connRDMABufNum = 36;
            connRDMAFragmentSize = 65536;
            # Bound the client's own reachability checks inside systemd's
            # outer mount timeout. A later path access can retry cleanly.
            sysMountSanityCheckMS = 5000;
          };
        };
      };
    };

    sops.secrets.beegfs-conn-auth = mkSecret "beegfs-conn-auth" { };
  };
}
