{config, lib, pkgs, ...}: let
  cfg = config.services.bluefield2-ipsec-ikev2;
  vppctl = "${config.services.vpp.package}/bin/vppctl";

  idType = {
    ipv4 = "ipv4";
    ipv6 = "ipv6";
    fqdn = "fqdn";
    rfc822 = "rfc822";
  };

  renderId = id: "${idType.${id.type}} ${id.value}";
  renderTs = direction: ts:
    "ikev2 profile set ${cfg.profile} traffic-selector ${direction} ip-range ${ts.startAddress} - ${ts.endAddress} port-range ${toString ts.startPort} - ${toString ts.endPort} protocol ${toString ts.protocol}";
  cli = command: "${vppctl} -s /run/vpp/cli.sock ${lib.escapeShellArg command}";

  authCommand =
    if cfg.authentication == "rsa-sig"
    then cli "ikev2 profile set ${cfg.profile} auth rsa-sig cert-file ${cfg.peerCertificateFile}"
    else ''
      key_hex="$(${pkgs.coreutils}/bin/od -An -tx1 -v ${lib.escapeShellArg cfg.sharedKeyFile} | ${pkgs.coreutils}/bin/tr -d '[:space:]')"
      [ -n "$key_hex" ]
      ${pkgs.coreutils}/bin/printf '%s\n' "ikev2 profile set ${cfg.profile} auth shared-key-mic hex $key_hex" | ${vppctl} -s /run/vpp/cli.sock
    '';

  setupScript = pkgs.writeShellScript "bluefield2-ipsec-ikev2-lab" ''
    set -eu

    # VPP starts its CLI socket asynchronously. Do not fail the boot if the
    # socket needs a few seconds, but do fail closed if it never appears.
    for _ in $(${pkgs.coreutils}/bin/seq 1 30); do
      if ${vppctl} -s /run/vpp/cli.sock show version >/dev/null 2>&1; then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    ${vppctl} -s /run/vpp/cli.sock show version >/dev/null

    # Make a manual restart of this lab unit safe after a VPP profile survives
    # for any reason; deleting a missing profile is deliberately harmless.
    ${cli "ikev2 profile del ${cfg.profile}"} >/dev/null 2>&1 || true
    ${cli "ikev2 profile add ${cfg.profile}"}
    ${authCommand}
    ${lib.optionalString (cfg.authentication == "rsa-sig") (cli "set ikev2 local key ${cfg.localPrivateKeyFile}")}
    ${cli "ikev2 profile set ${cfg.profile} id local ${renderId cfg.localIdentity}"}
    ${cli "ikev2 profile set ${cfg.profile} id remote ${renderId cfg.remoteIdentity}"}
    ${lib.optionalString (cfg.localTrafficSelector != null) (cli (renderTs "local" cfg.localTrafficSelector))}
    ${lib.optionalString (cfg.remoteTrafficSelector != null) (cli (renderTs "remote" cfg.remoteTrafficSelector))}
    ${lib.optionalString (cfg.tunnelInterface != null) (cli "ikev2 profile set ${cfg.profile} tunnel ${cfg.tunnelInterface}")}
    ${lib.optionalString cfg.udpEncapsulation (cli "ikev2 profile set ${cfg.profile} udp-encap")}
    ${cli "ikev2 profile set ${cfg.profile} ike-crypto-alg ${cfg.ikeEncryption} ${toString cfg.ikeKeyBits} ike-dh ${cfg.ikeDh}"}
    ${cli "ikev2 profile set ${cfg.profile} esp-crypto-alg ${cfg.espEncryption} ${toString cfg.espKeyBits}"}
    ${cli "ikev2 set liveness ${toString cfg.livenessPeriod} ${toString cfg.livenessRetries}"}
  '';

  selectorType = lib.types.submodule {
    options = {
      startAddress = lib.mkOption {
        type = lib.types.str;
        description = "First address in the IKEv2 traffic-selector range.";
      };
      endAddress = lib.mkOption {
        type = lib.types.str;
        description = "Last address in the IKEv2 traffic-selector range.";
      };
      startPort = lib.mkOption {
        type = lib.types.port;
        description = "First port in the traffic-selector range.";
      };
      endPort = lib.mkOption {
        type = lib.types.port;
        description = "Last port in the traffic-selector range.";
      };
      protocol = lib.mkOption {
        type = lib.types.ints.between 0 255;
        default = 0;
        description = "IP protocol number; zero means any protocol.";
      };
    };
  };

  identityType = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum (builtins.attrNames idType);
        description = "VPP IKEv2 identity encoding.";
      };
      value = lib.mkOption {
        type = lib.types.str;
        description = "Identity value, without shell quoting.";
      };
    };
  };
in {
  options.services.bluefield2-ipsec-ikev2 = {
    enable = lib.mkEnableOption "the opt-in BlueField VPP-native IKEv2 lab";

    kernelOffload.enable = lib.mkEnableOption "the separate Linux mlx5 IPsec crypto-offload kernel configuration";

    profile = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_]+";
      default = "bluefield2_lab";
      description = "VPP IKEv2 profile name.";
    };
    authentication = lib.mkOption {
      type = lib.types.enum ["rsa-sig" "shared-key-mic"];
      default = "rsa-sig";
      description = ''
        Authentication mode. rsa-sig uses the peer certificate as a pinned
        public key; shared-key-mic reads a PSK at runtime. VPP's plugin has no
        EAP/CA pool or certificate-chain configuration, so rsa-sig is not yet
        a general iPhone road-warrior solution.
      '';
    };
    peerCertificateFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime path to the peer certificate/public key for rsa-sig.";
    };
    sharedKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime path to a PSK; converted to hex only while configuring VPP.";
    };
    localPrivateKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime path to VPP's local private key (never put this in the Nix store).";
    };
    localIdentity = lib.mkOption {
      type = lib.types.nullOr identityType;
      default = null;
      description = "Local IKEv2 identity.";
    };
    remoteIdentity = lib.mkOption {
      type = lib.types.nullOr identityType;
      default = null;
      description = "Pinned remote IKEv2 identity; VPP requires this for responder profiles.";
    };
    localTrafficSelector = lib.mkOption {
      type = lib.types.nullOr selectorType;
      default = null;
      description = "Local protected traffic range. Supply from centralized network data.";
    };
    remoteTrafficSelector = lib.mkOption {
      type = lib.types.nullOr selectorType;
      default = null;
      description = "Remote protected traffic range. Supply from centralized network data.";
    };
    tunnelInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Existing VPP tunnel interface; null lets IKEv2 create a p2p IPIP tunnel.";
    };
    udpEncapsulation = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Force VPP UDP encapsulation; leave false for automatic IKEv2 NAT-T detection.";
    };
    ikeEncryption = lib.mkOption {
      type = lib.types.enum ["aes-gcm-16"];
      default = "aes-gcm-16";
      description = "IKE encryption; VPP's native AES-GCM path is used on Cortex-A72.";
    };
    ikeKeyBits = lib.mkOption {
      type = lib.types.enum [128 256];
      default = 256;
      description = "IKE AES key size.";
    };
    ikeDh = lib.mkOption {
      type = lib.types.enum ["modp-2048" "modp-3072" "ecp-256"];
      default = "modp-2048";
      description = "IKE Diffie-Hellman group.";
    };
    espEncryption = lib.mkOption {
      type = lib.types.enum ["aes-gcm-16"];
      default = "aes-gcm-16";
      description = "ESP encryption; AES-GCM is the only BlueField crypto-offload algorithm.";
    };
    espKeyBits = lib.mkOption {
      type = lib.types.enum [128 256];
      default = 256;
      description = "ESP AES key size.";
    };
    livenessPeriod = lib.mkOption {
      type = lib.types.ints.positive;
      default = 20;
      description = "IKEv2 liveness interval in seconds.";
    };
    livenessRetries = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Maximum IKEv2 liveness retries.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.kernelOffload.enable {
      # INET{,6}_ESP_OFFLOAD are modules in the opt-in kernel; loading them
      # makes the mlx5 XFRM callbacks available after mlx5_core probes.
      boot.kernelModules = ["esp4_offload" "esp6_offload"];
    })
    (lib.mkIf cfg.enable {
      services.vpp.settings.plugins.plugin."ikev2_plugin.so".enable = true;

    systemd.services.vpp-ikev2-lab = {
      description = "Configure opt-in VPP-native IKEv2 lab profile";
      wantedBy = ["multi-user.target"];
      after = ["vpp.service" "sops-install-secrets.service"];
      requires = ["vpp.service"];
      partOf = ["vpp.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = setupScript;
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "2s";
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        UMask = "0077";
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
      };
    };

      assertions = [
      {
        assertion = cfg.authentication != "rsa-sig" || cfg.localPrivateKeyFile != null;
        message = "services.bluefield2-ipsec-ikev2.localPrivateKeyFile is required for rsa-sig.";
      }
      {
        assertion = cfg.localIdentity != null && cfg.remoteIdentity != null;
        message = "VPP IKEv2 requires explicit localIdentity and remoteIdentity values.";
      }
      {
        assertion = cfg.localTrafficSelector != null && cfg.remoteTrafficSelector != null;
        message = "VPP IKEv2 lab requires explicit traffic selectors; derive them from network definitions.";
      }
      {
        assertion =
          (cfg.authentication == "rsa-sig" && cfg.peerCertificateFile != null)
          || (cfg.authentication == "shared-key-mic" && cfg.sharedKeyFile != null);
        message = "VPP IKEv2 authentication needs a runtime peerCertificateFile or sharedKeyFile.";
      }
      {
        assertion = builtins.all (path: path == null || lib.hasPrefix "/run/" path) [
          cfg.localPrivateKeyFile
          cfg.peerCertificateFile
          cfg.sharedKeyFile
        ];
        message = "VPP IKEv2 credentials must be injected below /run (for example by sops-nix), never embedded in the Nix store.";
      }
      ];
    })
  ];
}
