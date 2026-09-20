{ config, inputs, lib, network, pkgs, ... }:
let
  model = import ../hellas-model.nix;
  executionPolicy = pkgs.writeText "hellas-qwen3-policy.json" (builtins.toJSON model.execution);
  nodes = lib.genAttrs [ "strix-1" "strix-2" "strix-3" "strix-4" ]
    (name: network.primaryIp network.hosts.${name});
in
{
  imports = [ inputs.hellas.nixosModules.default ];

  home-manager.users.grw = { lib, ... }: {
    programs.opencode.telemetry.enable = true;
    home.activation.hellasOpenCode = lib.hm.dag.entryAfter [ "qwen38AgentModels" ] ''
      opencode_config="$HOME/.config/opencode/config.json"
      ${pkgs.jq}/bin/jq --slurpfile hellas ${./hellas-opencode.json} \
        '.model = $hellas[0].model | .small_model = $hellas[0].small_model | .provider.hellas = $hellas[0].provider.hellas' \
        "$opencode_config" > "$opencode_config.new"
      ${pkgs.coreutils}/bin/chmod 0600 "$opencode_config.new"
      ${pkgs.coreutils}/bin/mv "$opencode_config.new" "$opencode_config"
    '';
  };
  networking.firewall.allowedTCPPorts = [ 8080 ];

  systemd.tmpfiles.rules = [
    "d /mnt/Home/hellas 0755 root root -"
    "d /mnt/Home/hellas/strix-1 0700 4951 4951 -"
    "d /mnt/Home/hellas/strix-2 0700 4952 4952 -"
    "d /mnt/Home/hellas/strix-3 0700 4953 4953 -"
    "d /mnt/Home/hellas/strix-4 0700 4954 4954 -"
    "d /mnt/Home/hellas/gateway 0700 4950 4950 -"
    "d /export/hellas 0711 root root -"
  ];

  # The general Home export squashes every client to UID 1000. Private
  # payment identities and journals need each node's actual service UID.
  fileSystems = lib.mapAttrs' (name: _: lib.nameValuePair "/export/hellas/${name}" {
    device = "/mnt/Home/hellas/${name}";
    fsType = "none";
    options = [ "bind" ];
    depends = [ "/mnt/Home" ];
  }) nodes // {
    "/var/lib/hellas-gateway" = {
      device = "/mnt/Home/hellas/gateway";
      fsType = "none";
      options = [ "bind" ];
      depends = [ "/mnt/Home" ];
    };
  };
  services.nfs.server.exports = ''
    /export/hellas 192.168.23.0/24(rw,nohide,all_squash,no_subtree_check)
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: ip:
      "/export/hellas/${name} ${ip}(rw,sync,nohide,no_subtree_check,root_squash)"
    ) nodes)}
  '';
  systemd.services.nfs-server.unitConfig.RequiresMountsFor =
    lib.mapAttrsToList (name: _: "/export/hellas/${name}") nodes;

  users.groups.hellas-gateway.gid = 4950;
  users.users.hellas-gateway = {
    uid = 4950;
    group = "hellas-gateway";
    isSystemUser = true;
  };
  systemd.services.hellas-gateway.environment.RUST_LOG = "warn,hellas_cli=info,hellas_executor=info";
  services.hellas.otel = {
    enable = true;
    collectorEndpoint = "http://127.0.0.1:4318";
    serviceName = "hellas-trex";
    sampleRate = 1.0;
  };
  systemd.services.hellas-gateway.preStart = ''
    umask 077
    for node in strix-1 strix-2 strix-4; do
      ${pkgs.jq}/bin/jq --slurpfile execution ${executionPolicy} \
        '.policies.execution += $execution[0] | .poll_ms = 1000' \
        "/var/lib/hellas-gateway/$node-work.json" > "/run/hellas-gateway/$node-work.json"
    done
    ${pkgs.jq}/bin/jq \
      '.providers |= map(.work_config |= sub("^/var/lib/hellas-gateway/"; "/run/hellas-gateway/")) | .timeout_secs = 3600 | .terminal_blocks = 32768 | .payment_blocks = 1024' \
      /var/lib/hellas-gateway/providers.json > /run/hellas-gateway/providers.json
    credential=/var/lib/hellas-gateway/bearer-token
    if [ ! -e "$credential" ]; then
      umask 077
      ${pkgs.openssl}/bin/openssl rand -hex 32 > "$credential"
    fi
  '';
  systemd.services.hellas-gateway.serviceConfig = {
    # environment build publishes owner-only files. Share this model descriptor
    # with the dedicated gateway user; account files keep their private modes.
    # Even a no-op chmod changes ctime and invalidates the providers' content
    # index. Repair permissions only when necessary.
    ExecStartPre = [ "+${pkgs.writeShellScript "hellas-model-permissions" ''
      set -eu
      if [ "$(${pkgs.coreutils}/bin/stat -c %a ${lib.escapeShellArg model.environment})" != 644 ]; then
        ${pkgs.coreutils}/bin/chmod 0644 ${lib.escapeShellArg model.environment}
      fi
    ''}" ];
    DynamicUser = lib.mkForce false;
    # Ownership and lifecycle belong to the NAS directory and bind mount.
    StateDirectory = lib.mkForce [];
    User = "hellas-gateway";
    Group = "hellas-gateway";
    TimeoutStopSec = 3660;
    RuntimeDirectory = "hellas-gateway";
    RuntimeDirectoryMode = "0755";
    ExecStartPost = [ "+${pkgs.coreutils}/bin/install -m 0600 -o grw -g users /var/lib/hellas-gateway/bearer-token /run/hellas-gateway/client-token" ];
  };

  services.hellas = {
    gateway = {
      enable = true;
      host = "192.168.23.8";
      port = 8080;
      causalLmEnvironment = model.environment;
      tokenizer = model.tokenizer;
      chatTemplate = model.chatTemplate;
      model = model.name;
      defaultMaxTokens = model.outputTokens;
      stopTokenIds = model.stopTokens;
      paidWorkConfig = "/run/hellas-gateway/providers.json";
      paidWorkJournalRoots = [ "/var/lib/hellas-gateway/work" ];
      bearerTokenFile = "/var/lib/hellas-gateway/bearer-token";
    };
  };
}
