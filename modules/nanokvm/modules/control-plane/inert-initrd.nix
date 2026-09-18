# Stay-in-initrd profile: replace systemd's stage-1 → stage-2 switch-root
# pipeline with no-ops. Used by `kernel-test` and `nbd-debug` flavors —
# they never need a real stage 2 because all the testing happens inside
# the initrd itself.
#
# Toggled by `nanokvm.usbControl.inertSwitchRoot.enable`. Lives outside
# `modules/usb-control.nix` so the umbrella module doesn't have a
# fileSystems/kernelParams override stash hidden inside it.
{
  config,
  lib,
  ...
}: let
  cfg = config.nanokvm.usbControl;

  # Replace each switch-root service's ExecStart with /bin/true. The
  # services still exist (they're load-bearing for systemd's target
  # graph), they just don't do anything.
  inertSwitchRoot = {
    overrideStrategy = "asDropinIfExists";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ["" "/bin/true"];
      RemainAfterExit = true;
    };
  };
in {
  options.nanokvm.usbControl.inertSwitchRoot.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Stay in the initrd: replace the standard initrd→stage-2
      switch-root services with no-op stubs. Used by kernel-test
      and nbd-debug, which only ever live in stage 1.
    '';
  };

  config = lib.mkIf cfg.inertSwitchRoot.enable {
    fileSystems = lib.mkForce {};
    hardware.deviceTree.enable = lib.mkForce false;

    boot.kernelParams = lib.mkForce (
      [
        "console=${
          if config.sg2002.kernel == "mainline"
            && config.sg2002.uart1Rescue.enable
          then "ttyS1"
          else "ttyS0"
        },115200"
        "console=ttyGS0,115200"
      ]
      ++ [
        "earlycon=sbi"
        "ignore_loglevel"
        "panic=10"
        "oops=panic"
      ]
    );

    boot.initrd.systemd.root = null;

    boot.initrd.systemd.services = lib.genAttrs [
      "initrd-find-nixos-closure"
      "initrd-nixos-activation"
      "initrd-switch-root"
      "initrd-cleanup"
      "initrd-parse-etc"
    ] (_: inertSwitchRoot);
  };
}
