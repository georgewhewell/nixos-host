{ config, lib, ... }:
# Fleet-wide crash/hang recovery baseline, factored out of per-host configs
# (previously duplicated in strix-halo and fuckup). Panic quickly on a fault and
# let the systemd + hardware watchdog reboot a wedged machine. Skipped in
# containers (no kernel, no /dev/watchdog).
#
# The hardware-watchdog DRIVER is platform-specific (sp5100_tco on AMD,
# intel_oc_wdt/iTCO_wdt on Intel, SoC-specific on ARM), but the kernel
# auto-binds the right one — verified: router/trex (AMD) expose "SP5100 TCO
# timer" and n100 (Intel) exposes "intel_oc_wdt" with no explicit module. So we
# deliberately do NOT load a module here; systemd RuntimeWatchdogSec uses
# /dev/watchdog0. (strix-halo/fuckup keep an explicit sp5100_tco belt-and-braces.)
#
# sysctls/timers use mkOptionDefault (weakest priority) so any host- or
# flake-input-specific definition wins without conflict — e.g. the
# nix-strix-halo module sets the same sysctls as mkDefault on the strix nodes.
lib.mkIf (!config.boot.isContainer) {
  boot.kernelParams = [
    "panic=5"
    "panic_on_oops=1"
    "softlockup_panic=1"
    "hung_task_panic=1"
    "nmi_watchdog=panic,1"
  ];

  boot.kernel.sysctl = {
    "kernel.panic" = lib.mkOptionDefault 5;
    "kernel.watchdog" = lib.mkOptionDefault 1;
    "kernel.panic_on_oops" = lib.mkOptionDefault 1;
    "kernel.softlockup_panic" = lib.mkOptionDefault 1;
    "kernel.hung_task_panic" = lib.mkOptionDefault 1;
    "kernel.nmi_watchdog" = lib.mkOptionDefault 1;
    "kernel.hardlockup_panic" = lib.mkOptionDefault 1;
    "kernel.panic_print" = lib.mkOptionDefault 63;
  };

  systemd.settings.Manager = {
    RuntimeWatchdogSec = lib.mkOptionDefault "15s";
    RebootWatchdogSec = lib.mkOptionDefault "30s";
    KExecWatchdogSec = lib.mkOptionDefault "30s";
  };
}
