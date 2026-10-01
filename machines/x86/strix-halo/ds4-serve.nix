# DeepSeek-V4.1 serving candidate on the four Strix Halo APUs. The packaged
# launcher validates the model snapshot and takes the shared GPU lock; this
# module supplies the qualified fleet rank order and normal NixOS lifecycle.
index:
{
  lib,
  pkgs,
  inputs,
  network,
  ...
}:
let
  hostName = "strix-${toString index}";
  self = network.hosts.${hostName};
  netboot = self.netboot or false;
  servingEnabled = netboot && (self.strix.ds4Serve or false);
  productionPackages = inputs.nix-strix-halo-ds4.packages.${pkgs.stdenv.hostPlatform.system};
  server = productionPackages.ds41-node;
  nodeRank =
    {
      "1" = 3;
      "3" = 0;
      "2" = 2;
      "4" = 1;
    }
    .${toString index};
  coordinator = network.ipOf "fabric" network.hosts.strix-3.addresses.fabric;
  # The existing /models mount pins the same RO snapshot UUID/NQN as the
  # qualified launcher. Its preflight verifies that identity, not an alias.
  model = "/models/DeepSeek-V4.1-Flash-hf-dba1be0a";
  cacheDir = "/mnt/Home/services/ds4-production/${hostName}/cache";
in
{
  systemd.services.ds4-serve = lib.mkIf servingEnabled {
    description = "Serve DeepSeek-V4.1 on Strix Halo rank ${toString nodeRank}";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "network-online.target"
      "nvme-trex-models.service"
    ];
    after = [
      "network-online.target"
      "remote-fs.target"
      "nvme-trex-models.service"
    ];
    unitConfig = {
      RequiresMountsFor = [
        model
        cacheDir
      ];
      ConditionPathIsDirectory = model;
      StartLimitBurst = 3;
      StartLimitIntervalSec = "1h";
    };
    environment = {
      DS41_MODEL_PATH = model;
      DS41_HEAD_ADDR = "${coordinator}:51041";
      DS41_NODE_RANK = toString nodeRank;
      # The head API remains on strix-3 localhost; clients use an explicit
      # tunnel to 127.0.0.1:31041, not the old fabric-wide port 30000.
      DS41_PORT = "31041";
      # The launcher creates runtime-specific compiler namespaces below this
      # persistent root. Do not reuse the old unversioned Triton directory.
      DS41_CACHE_ROOT = "${cacheDir}/gfx1151";
      HOME = cacheDir;
      XDG_RUNTIME_DIR = "/run/ds4-production";
      HF_HOME = "${cacheDir}/huggingface";
    };
    serviceConfig = {
      Type = "simple";
      User = "grw";
      Group = "users";
      RuntimeDirectory = "ds4-production";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p ${cacheDir}/huggingface"
      ];
      # ExecStart retains the complete qualified runtime in the system closure.
      ExecStart = lib.getExe server;
      Restart = "on-failure";
      RestartPreventExitStatus = "2";
      RestartSec = "30s";
      KillMode = "mixed";
      TimeoutStartSec = "30min";
      TimeoutStopSec = "5min";
      LimitMEMLOCK = "infinity";
      TasksMax = "infinity";
      NoNewPrivileges = true;
      # /tmp/ds41-gpu.lock must be the same inode used by manual/component jobs.
      # The launcher owns the flock lifetime; never remove the lock file.
      PrivateTmp = false;
      UMask = "0077";
    };
  };
}
