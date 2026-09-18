# Shared bash helpers + target-script builder used by the target-side
# control-plane modules (`modules/control-plane/*.nix`).
#
# Plain Nix function — NOT a NixOS module. Imported by the control-plane
# modules that emit shell scripts:
#
#   targetLib = import ./target-script-lib.nix { inherit lib pkgs config; };
#   inherit (targetLib) mkTargetScript shellLib targetTools kernelIsMainline;
#
# Lives outside `lib/` because it depends on `config.sg2002.kernel` (to
# decide whether to include kexec-tools etc on PATH), which is a NixOS
# module-eval artifact.
{
  lib,
  pkgs,
  config,
}: let
  protocol = import ../../lib/protocol.nix;
  kernelIsMainline = config.sg2002.kernel == "mainline";

  # Tools the target-side scripts need on PATH. The specialized tools
  # come BEFORE busybox so their applets shadow the busybox stubs —
  # busybox ships an `nbd-client` that doesn't understand `-R` etc.
  # (Mainline kernel only; vendor kernel does not have working kexec.)
  targetTools =
    lib.optionals kernelIsMainline [
      pkgs.nbd-client-minimal
      pkgs.kexec-tools
      pkgs.dtc
    ]
    ++ [pkgs.busybox];

  # Shell prelude sourced by every target-side script. Defines protocol
  # constants and helper functions, all using bare command names — the
  # caller is expected to have set PATH first.
  shellLib = ''
    nanokvm_target_mac=${protocol.targetMac}
    nanokvm_host_mac=${protocol.hostMac}
    nanokvm_target_ip=${protocol.targetIp}
    nanokvm_host_ip=${protocol.hostIp}
    nanokvm_prefix=${protocol.prefix}
    nanokvm_port_shell=${toString protocol.ports.debugShell}
    nanokvm_port_status=${toString protocol.ports.statusSink}
    nanokvm_port_kexec=${toString protocol.ports.kexecCtrl}
    nanokvm_port_nbd_rootfs=${toString protocol.ports.nbdRootfs}
    nanokvm_port_nbd_payload=${toString protocol.ports.nbdPayload}

    # Locate the USB gadget interface. Prefer a MAC match, fall back to
    # the first ARPHRD_ETHER (type 1) interface — that excludes loopback
    # (772) and tunnel devices like sit0 (776).
    nanokvm_find_iface() {
      local desired="''${1:-$nanokvm_target_mac}" path observed
      for path in /sys/class/net/*; do
        [ -r "$path/address" ] || continue
        observed="$(cat "$path/address" 2>/dev/null || true)"
        if [ "$observed" = "$desired" ]; then
          printf '%s\n' "''${path##*/}"
          return 0
        fi
      done
      for path in /sys/class/net/*; do
        [ -r "$path/type" ] || continue
        [ "$(cat "$path/type" 2>/dev/null || true)" = 1 ] || continue
        printf '%s\n' "''${path##*/}"
        return 0
      done
      return 1
    }

    nanokvm_wait_iface() {
      local desired="''${1:-$nanokvm_target_mac}"
      local timeout="''${2:-30}"
      local iface attempts=$((timeout * 10))
      for _ in $(seq 1 "$attempts"); do
        iface="$(nanokvm_find_iface "$desired" 2>/dev/null || true)"
        if [ -n "$iface" ]; then
          printf '%s\n' "$iface"
          return 0
        fi
        sleep 0.1
      done
      return 1
    }

    # Send stdin to the host status sink. Always returns 0 — losing a
    # status update is non-fatal.
    nanokvm_push_status() {
      nc -w "''${1:-2}" "$nanokvm_host_ip" "$nanokvm_port_status" \
        >/dev/null 2>&1 || true
    }
  '';

  mkTargetScript = name: body:
    pkgs.writeShellScript name ''
      set -eu
      export PATH=${lib.makeBinPath targetTools}
      ${shellLib}

      ${body}
    '';
in {
  inherit
    targetTools
    kernelIsMainline
    shellLib
    mkTargetScript
    protocol
    ;
}
