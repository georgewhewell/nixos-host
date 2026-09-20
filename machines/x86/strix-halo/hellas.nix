{ config, inputs, lib, network, pkgs, ... }:
let
  model = import ../hellas-model.nix;
  executionPolicy = pkgs.writeText "hellas-qwen3-policy.json" (builtins.toJSON model.execution);
  hostName = config.networking.hostName;
  index = lib.toInt (lib.removePrefix "strix-" hostName);
  cliArgs = (import (inputs.hellas + "/nix/modules/hellas.nix") {
    self = inputs.hellas;
  }).mkServeArgs { inherit lib; serve = config.services.hellas; };
  serve = pkgs.writeShellScript "hellas-strix-serve" ''
    set -eu
    ordinal=0
    for node in /sys/class/kfd/kfd/topology/nodes/*; do
      simd=$(${pkgs.gawk}/bin/awk '$1 == "simd_count" { print $2 }' "$node/properties")
      [ "''${simd:-0}" -gt 0 ] || continue
      device=$(${pkgs.gawk}/bin/awk '$1 == "device_id" { print $2 }' "$node/properties")
      if [ "$device" = 5510 ]; then
        export HIP_VISIBLE_DEVICES="$ordinal"
        exec ${lib.escapeShellArgs ([ "${config.services.hellas.package}/bin/hellas-cli" ] ++ cliArgs)}
      fi
      ordinal=$((ordinal + 1))
    done
    echo "Hellas could not find the Strix APU in KFD topology" >&2
    exit 1
  '';
in
{
  imports = [ inputs.hellas.nixosModules.default ];

  # Only identity, content indexes and payment journals survive a boot.
  # Nix and compiler scratch remain on the freshly formatted SPDK volume.
  users.groups.hellas.gid = 4950 + index;
  users.users.hellas = {
    uid = 4950 + index;
    group = "hellas";
    isSystemUser = true;
  };
  fileSystems."/var/lib/hellas" = {
    device = "${network.primaryIp network.hosts.trex}:/hellas/${hostName}";
    fsType = "nfs4";
    options = [ "_netdev" "hard" "nfsvers=4.2" ];
  };
  systemd.tmpfiles.rules = [ "d /tmp/hellas 0700 hellas hellas -" ];

  services.hellas = {
    enable = true;
    port = 31145;
    openFirewall = true;
    identityPath = "/var/lib/hellas/.hellas/identity";
    executePolicy = [ model.execution.allowed_environment ];
    content = [ model.environment ];
    contentRoots = [ model.contentRoot ];
    gpuBackend = "hip";
    gpuSessionAssetBytes = 80 * 1024 * 1024 * 1024;
    gpuMaxGenerationCapacity = model.contextTokens;
    # Catena counts allocations across a whole forward pass, including
    # freed intermediates. Qwen's longer prompts exceed the 8 GiB default.
    gpuMaxGenerationDeviceBytes = 64 * 1024 * 1024 * 1024;
    workConfigFile = "/run/hellas/work.json";
    metricsPort = 9400;
    otel = {
      enable = true;
      collectorEndpoint = "http://${network.primaryIp network.hosts.trex}:4318";
      serviceName = "hellas-${hostName}";
      sampleRate = 1.0;
    };
    graffiti = hostName;
  };
  systemd.services.hellas = {
    preStart = ''
      umask 077
      ${pkgs.jq}/bin/jq --slurpfile execution ${executionPolicy} \
        '.policies.execution += $execution[0] | .poll_ms = 1000' \
        /var/lib/hellas/work.json > /run/hellas/work.json
    '';
    environment.TMPDIR = lib.mkForce "/tmp/hellas";
    environment.RUST_LOG = "warn,hellas_cli=info,hellas_executor=info";
    serviceConfig = {
      ExecStart = lib.mkForce serve;
      RuntimeDirectory = "hellas";
      RuntimeDirectoryMode = "0700";
      DynamicUser = lib.mkForce false;
      # The NFS directory already has its fixed UID. Root-squashed clients
      # cannot apply systemd's StateDirectory ownership/mode changes to it.
      StateDirectory = lib.mkForce [];
      User = "hellas";
      Group = "hellas";
    };
  };
}
