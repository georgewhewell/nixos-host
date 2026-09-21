{
  config,
  inputs,
  lib,
  network,
  pkgs,
  ...
}:
let
  model = {
    name = "SmolLM2-135M-Instruct";
    contentRoot = "/mnt/Home/models/hellas/smollm2-135m-instruct";
    environment = "/mnt/Home/models/hellas/smollm2-135m-instruct/model.environment";
    tokenizer = "/mnt/Home/models/hellas/smollm2-135m-instruct/tokenizer.json";
    chatTemplate = "smollm2";
    contextTokens = 8192;
    outputTokens = 512;
    stopTokens = [ 2 ];
    manifest = "27ee6352beace2cdd9011392a4a8a3b505fe74de7737a01d2c6029916852d002";
  };
  nodes = lib.genAttrs [ "strix-1" "strix-2" "strix-3" "strix-4" ] (
    name: network.primaryIp network.hosts.${name}
  );
  gatewayCli = "${config.services.hellas.gateway.package}/bin/hellas-cli";
  smollmContent = pkgs.writeShellScript "hellas-smollm2-content" ''
    set -eu

    root=${lib.escapeShellArg model.contentRoot}
    ${pkgs.coreutils}/bin/install -d -m 0755 "$root"

    install_source() {
      expected=$1
      source=$2
      target=$3
      if [ -e "$target" ]; then
        printf '%s  %s\n' "$expected" "$target" | ${pkgs.coreutils}/bin/sha256sum --check --strict
      else
        ${pkgs.coreutils}/bin/install -m 0444 "$source" "$target"
      fi
      ${pkgs.coreutils}/bin/chmod 0444 "$target"
    }

    download() {
      expected=$1
      url=$2
      target=$3
      if [ -e "$target" ]; then
        printf '%s  %s\n' "$expected" "$target" | ${pkgs.coreutils}/bin/sha256sum --check --strict
        ${pkgs.coreutils}/bin/chmod 0444 "$target"
        return
      fi
      temporary=$(${pkgs.coreutils}/bin/mktemp "$target.download.XXXXXX")
      ${pkgs.curl}/bin/curl --fail --location --retry 4 --retry-all-errors --output "$temporary" "$url"
      printf '%s  %s\n' "$expected" "$temporary" | ${pkgs.coreutils}/bin/sha256sum --check --strict
      ${pkgs.coreutils}/bin/chmod 0444 "$temporary"
      ${pkgs.coreutils}/bin/mv -n -- "$temporary" "$target"
      printf '%s  %s\n' "$expected" "$target" | ${pkgs.coreutils}/bin/sha256sum --check --strict
    }

    install_source \
      438723c4b22d74dbd17cba314421f589c1d9d686542d3444d69919767fedec7d \
      ${lib.escapeShellArg "${inputs.catena-runner}/models/smollm2/smollm2.hex"} \
      "$root/smollm2.hex"
    ${pkgs.coreutils}/bin/install -m 0444 \
      ${lib.escapeShellArg "${inputs.hellas-gateway}/examples/smollm2.environment.toml"} \
      "$root/smollm2.toml"

    download \
      5af571cbf074e6d21a03528d2330792e532ca608f24ac70a143f6b369968ab8c \
      https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct/resolve/12fd25f77366fa6b3b4b768ec3050bf629380bac/model.safetensors?download=true \
      "$root/model.safetensors"
    download \
      9ca9acddb6525a194ec8ac7a87f24fbba7232a9a15ffa1af0c1224fcd888e47c \
      https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct/resolve/12fd25f77366fa6b3b4b768ec3050bf629380bac/tokenizer.json?download=true \
      "$root/tokenizer.json"

    ${gatewayCli} environment build \
      --program "$root/smollm2.hex" \
      --settings "$root/smollm2.toml" \
      --out "$root/model.environment"
    ${gatewayCli} environment inspect --environment "$root/model.environment" \
      | ${pkgs.gnugrep}/bin/grep -Fq ${lib.escapeShellArg model.manifest}
    ${pkgs.coreutils}/bin/chmod 0444 "$root/model.environment"
  '';
in
{
  imports = [ inputs.hellas-gateway.nixosModules.default ];

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
  fileSystems =
    lib.mapAttrs' (
      name: _:
      lib.nameValuePair "/export/hellas/${name}" {
        device = "/mnt/Home/hellas/${name}";
        fsType = "none";
        options = [ "bind" ];
        depends = [ "/mnt/Home" ];
      }
    ) nodes
    // {
      "/var/lib/hellas-gateway" = {
        device = "/mnt/Home/hellas/gateway";
        fsType = "none";
        options = [ "bind" ];
        depends = [ "/mnt/Home" ];
      };
    };
  services.nfs.server.exports = ''
    /export/hellas 192.168.23.0/24(rw,nohide,all_squash,no_subtree_check)
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: ip: "/export/hellas/${name} ${ip}(rw,sync,nohide,no_subtree_check,root_squash)"
      ) nodes
    )}
  '';
  systemd.services.nfs-server.unitConfig.RequiresMountsFor = lib.mapAttrsToList (
    name: _: "/export/hellas/${name}"
  ) nodes;

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
  systemd.services.hellas-smollm2-content = {
    description = "Provision the pinned SmolLM2 Instruct content";
    before = [ "hellas-gateway.service" ];
    requiredBy = [ "hellas-gateway.service" ];
    unitConfig.RequiresMountsFor = model.contentRoot;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      exec ${smollmContent}
    '';
  };
  systemd.services.hellas-gateway = {
    requires = [ "hellas-smollm2-content.service" ];
    after = [ "hellas-smollm2-content.service" ];
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      # Ownership and lifecycle belong to the NAS directory and bind mount.
      StateDirectory = lib.mkForce [ ];
      User = "hellas-gateway";
      Group = "hellas-gateway";
      RuntimeDirectory = "hellas-gateway";
      RuntimeDirectoryMode = lib.mkForce "0755";
      ExecStartPost = [
        "+${pkgs.coreutils}/bin/install -m 0600 -o grw -g users /var/lib/hellas-gateway/bearer-token /run/hellas-gateway/client-token"
      ];
    };
  };

  services.hellas = {
    environment.HIP_VISIBLE_DEVICES = "0";
    gateway = {
      enable = true;
      host = "192.168.23.8";
      port = 8080;
      allowRemote = true;
      causalLmEnvironment = model.environment;
      tokenizer = model.tokenizer;
      chatTemplate = model.chatTemplate;
      model = model.name;
      defaultMaxTokens = model.outputTokens;
      stopTokenIds = model.stopTokens;
      local = true;
      contentRoots = [ model.contentRoot ];
      contentIndex = "/var/lib/hellas-gateway/content.index";
      bearerTokenFile = "/var/lib/hellas-gateway/bearer-token";
    };
  };
}
