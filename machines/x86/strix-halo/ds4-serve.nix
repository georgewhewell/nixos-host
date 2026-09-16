# DeepSeek-V4 production serving on the four Strix Halo APUs. The packaged
# launcher owns the exact rank -> host -> GPU/BDF safety checks; this module
# supplies only the fleet rank and normal NixOS lifecycle.
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
  servingEnabled = netboot && (self.strix.ds4Serve or true);
  productionPackages = inputs.nix-strix-halo-ds4.packages.${pkgs.stdenv.hostPlatform.system};
  server = productionPackages.sglang-dsv4-halo4;
  agent = productionPackages.ds4-opencode;
  nodeRank =
    {
      "1" = 0;
      "3" = 1;
      "2" = 2;
      "4" = 3;
    }
    .${toString index};
  coordinator = network.ipOf "fabric" network.hosts.strix-1.addresses.fabric;
  model = "/models/DeepSeek-V4-Flash-0731-hf-9e165c30";
  cacheDir = "/mnt/Home/services/ds4-production/${hostName}/cache";
in
{
  # ExecStart roots the complete server closure in the netboot image. The
  # existing closureInfo registration makes it valid before nix-daemon starts,
  # so a client never needs to copy it into the 2 GiB writable overlay.
  environment.systemPackages = [ agent ];
  environment.variables = {
    DS4_OPENAI_BASE_URL = "http://${coordinator}:30000/v1";
    DS4_OPENAI_MODEL = "deepseek-v4-flash";
  };

  systemd.services.ds4-serve = lib.mkIf servingEnabled {
    description = "Serve DeepSeek-V4 on Strix Halo rank ${toString nodeRank}";
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
      DS4_MODEL = model;
      DS4_DIST_INIT_ADDR = "${coordinator}:29500";
      DS4_NODE_RANK = toString nodeRank;
      DS4_FABRIC_IFACE = "cx5fabric0";
      # Keep the unauthenticated OpenAI endpoint on the private model fabric;
      # it must not also listen on the LAN or Thunderbolt links.
      DS4_HOST = network.ipOf "fabric" self.addresses.fabric;
      DS4_CONTEXT_LENGTH = "65536";
      DS4_PORT = "30000";
      DS4_SERVED_MODEL_NAME = "deepseek-v4-flash";
      HOME = cacheDir;
      XDG_CACHE_HOME = cacheDir;
      XDG_RUNTIME_DIR = "/run/ds4-production";
      HF_HOME = "${cacheDir}/huggingface";
      TRITON_CACHE_DIR = "${cacheDir}/triton";
    };
    serviceConfig = {
      Type = "simple";
      User = "grw";
      Group = "users";
      RuntimeDirectory = "ds4-production";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p ${cacheDir}/huggingface ${cacheDir}/triton"
      ];
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
      PrivateTmp = true;
      UMask = "0077";
    };
  };

  networking.firewall.interfaces.cx5fabric0.allowedTCPPorts = lib.mkIf (servingEnabled && index == 1) [
    30000
  ];
}
