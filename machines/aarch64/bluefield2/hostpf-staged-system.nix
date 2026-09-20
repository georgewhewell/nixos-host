{
  config,
  lib,
  network,
  pkgs,
  ...
}:
{
  imports = [ ./hostpf-system.nix ];

  # Attended review wrapper around the guard-free production closure.

  # Mark only this bootable experiment. The guard is inert if somebody
  # accidentally activates the closure on the running production kernel.
  boot.kernelParams = [ "bluefield.hostpf-test=1" ];

  # A test boot must preserve WAN or return to the permanent default.  Host-PF
  # failure is diagnostic state, not a reason to throw away the live system: once
  # WAN is healthy, keep watching it while leaving the failed representor in
  # place for inspection. The deployment procedure keeps the currently
  # accepted production entry as the permanent default and selects this
  # closure through systemd-boot's one-shot entry.
  systemd.services.bluefield-hostpf-boot-guard = {
    description = "Revert an uncommitted BlueField host-PF test boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "vpp.service" ];
    unitConfig.ConditionKernelCommandLine = "bluefield.hostpf-test=1";
    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.systemd
      config.services.vpp.package
    ];
    serviceConfig = {
      Type = "simple";
      Restart = "no";
      TimeoutStopSec = "10s";
    };
    script = ''
      set -u
      commit=/run/bluefield-hostpf-test-commit
      wan_health=/run/bluefield-hostpf-test-wan-health
      hostpf_health=/run/bluefield-hostpf-test-health
      rm -f "$commit" "$wan_health" "$hostpf_health"

      wan_was_healthy=false
      wan_failures=0
      second=0
      while true; do
        second=$((second + 1))
        if test -e "$commit"; then
          echo "host-PF test boot explicitly committed after $second seconds"
          exit 0
        fi

        if systemctl is-active --quiet vpp.service \
           && vppctl show interface bf0 2>/dev/null \
                | grep -q '^bf0[[:space:]].*[[:space:]]up[[:space:]]' \
           && vppctl show ip fib 0.0.0.0/0 2>/dev/null \
                | grep -q 'DHCP refs:.*active'; then
          printf 'WAN healthy at second %s\n' "$second" >"$wan_health"
          wan_was_healthy=true
          wan_failures=0
        else
          rm -f "$wan_health"
          wan_failures=$((wan_failures + 1))
          if { ! $wan_was_healthy && test "$second" -ge 120; } \
             || { $wan_was_healthy && test "$wan_failures" -ge 30; }; then
            echo "WAN dataplane unhealthy during host-PF test; rebooting to permanent default" >&2
            systemctl reboot
            exit 1
          fi
        fi

        if vppctl show interface '${network.routing.hostPf.dpu.vppName}' 2>/dev/null \
                | grep -q '^${network.routing.hostPf.dpu.vppName}[[:space:]].*[[:space:]]up[[:space:]]' \
           && vppctl ping '${network.ipOf network.routing.hostPf.network network.routing.hostPf.router.address}' \
                repeat 1 interval 0.1 2>/dev/null \
                | grep -q '1 received'; then
          printf 'host-PF healthy at second %s\n' "$second" >"$hostpf_health"
        else
          rm -f "$hostpf_health"
        fi

        sleep 1
      done
    '';
  };

  # The ordinary eMMC-friendly profile keeps only a 1 MiB volatile journal.
  # A failed networking experiment then destroys its own evidence on rollback.
  # Persist a small, bounded journal in this staged closure only.
  services.journald = {
    settings.Journal = {
      Storage = lib.mkForce "persistent";
      SystemMaxUse = lib.mkForce "128M";
      SystemMaxFileSize = lib.mkForce "16M";
      RuntimeMaxUse = lib.mkForce "16M";
      RuntimeMaxFileSize = lib.mkForce "4M";
    };
  };
}
