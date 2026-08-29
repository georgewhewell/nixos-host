{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.bluefield2-vpp-cnat-lab;
  vppctl = "${config.services.vpp.package}/bin/vppctl";
  startLab = pkgs.writeShellApplication {
    name = "bluefield-vpp-cnat-lab-start";
    runtimeInputs = [config.services.vpp.package pkgs.gnugrep];
    text = ''
      set -euo pipefail

      # vppctl exits zero even when the CLI replies with "unknown input" or a
      # parse error. Treat those replies as failures so systemd cannot report
      # a configured lab when VPP rejected every command.
      vppctl_checked() {
        local output
        if ! output=$(vppctl "$@" 2>&1); then
          printf '%s\n' "$output" >&2
          return 1
        fi
        case "$output" in
          *"unknown input"*|*"unknown interface"*|*"parse error"*|*"failed"*|*"not found"*|*"no snat policy"*)
            printf '%s\n' "$output" >&2
            return 1
            ;;
        esac
        if [ -n "$output" ]; then
          printf '%s\n' "$output"
        fi
      }

      if ! vppctl show interface | grep -Eq '^bf0\.3901[[:space:]]'; then
        vppctl_checked create sub-interfaces bf0 3901
      fi
      if ! vppctl show interface | grep -Eq '^bf0\.3902[[:space:]]'; then
        vppctl_checked create sub-interfaces bf0 3902
      fi

      vppctl_checked set interface mtu packet 9000 bf0.3901
      vppctl_checked set interface mtu packet 1500 bf0.3902
      vppctl_checked set interface state bf0.3901 up
      vppctl_checked set interface state bf0.3902 up

      if ! vppctl show interface address bf0.3901 | grep -Fq '198.18.10.1/24'; then
        vppctl_checked set interface ip address bf0.3901 198.18.10.1/24
      fi
      if ! vppctl show interface address bf0.3902 | grep -Fq '203.0.113.2/24'; then
        vppctl_checked set interface ip address bf0.3902 203.0.113.2/24
      fi

      # CNAT stores sessions in a shared flow hash and therefore does not
      # funnel every flow from one client address through one handoff worker.
      # It is attached only to the documentation-prefix lab interface.
      vppctl_checked set cnat snat-policy addr bf0.3902
      vppctl_checked set cnat snat-policy if-pfx
      vppctl_checked set cnat snat-policy if table include-v4 bf0.3901
      vppctl_checked set cnat snat-policy prefix 198.18.0.0/15
      vppctl_checked set interface feature bf0.3901 cnat-snat-ip4 arc ip4-unicast

      vppctl_checked show cnat snat-policy
      vppctl show interface address bf0.3901 | grep -Fq '198.18.10.1/24'
      vppctl show interface address bf0.3902 | grep -Fq '203.0.113.2/24'
    '';
  };
  stopLab = pkgs.writeShellApplication {
    name = "bluefield-vpp-cnat-lab-stop";
    runtimeInputs = [config.services.vpp.package];
    text = ''
      set -u

      vppctl set interface feature bf0.3901 cnat-snat-ip4 arc ip4-unicast disable 2>/dev/null || true
      vppctl set cnat snat-policy if del table include-v4 bf0.3901 2>/dev/null || true
      vppctl set cnat snat-policy prefix del 198.18.0.0/15 2>/dev/null || true
      vppctl set interface state bf0.3901 down 2>/dev/null || true
      vppctl set interface state bf0.3902 down 2>/dev/null || true
      vppctl delete sub-interface bf0.3901 2>/dev/null || true
      vppctl delete sub-interface bf0.3902 2>/dev/null || true
    '';
  };
  reportLab = pkgs.writeShellApplication {
    name = "bluefield-vpp-cnat-lab-report";
    runtimeInputs = [config.services.vpp.package];
    text = ''
      set -euo pipefail
      vppctl show cnat snat-policy
      vppctl show cnat session verbose
      vppctl show runtime
      vppctl show errors
    '';
  };
in {
  options.services.bluefield2-vpp-cnat-lab.enable = lib.mkEnableOption ''
    the isolated CNAT performance lab on VPP VLANs 3901 and 3902
  '';

  config = lib.mkIf cfg.enable {
    # Merely loading CNAT changes no forwarding path. The feature is attached
    # only when the operator starts bluefield-vpp-cnat-lab.service.
    services.vpp.settings = {
      plugins.plugin."cnat_plugin.so".enable = true;
      cnat = {
        session-max-age = 60;
        tcp-max-age = 3600;
        # VPP 26.06 sizes the shared session bihash from session-max.  The
        # session-db-* knobs still shown in cnat.rst are no longer accepted by
        # the startup parser (see src/plugins/cnat/cnat_types.c).
        session-max = 1048576;
        translation-db-memory = "64M";
        translation-db-buckets = 65536;
        snat-db-memory = "64M";
        snat-db-buckets = 65536;
      };
    };

    systemd.services.bluefield-vpp-cnat-lab = {
      description = "Isolated VPP CNAT performance lab";
      after = ["vpp.service"];
      requires = ["vpp.service"];
      partOf = ["vpp.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${startLab}/bin/bluefield-vpp-cnat-lab-start";
        ExecStop = "${stopLab}/bin/bluefield-vpp-cnat-lab-stop";
      };
    };

    environment.systemPackages = [startLab stopLab reportLab];
  };
}
