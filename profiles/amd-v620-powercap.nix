{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.amdgpu.v620PowerCap;
  # Copy just the patch into the store, so unrelated fleet config edits do
  # not invalidate a full kernel build through the enclosing flake path.
  kernelPatch = builtins.path {
    path = ./patches/amdgpu-v620-powercap-min-120w.patch;
    name = "amdgpu-v620-powercap-min-120w.patch";
  };
in
{
  options.hardware.amdgpu.v620PowerCap = {
    enable = lib.mkEnableOption "Radeon PRO V620 lower power limits";
    watts = lib.mkOption {
      type = lib.types.ints.between 120 250;
      default = 180;
      description = "PPT cap in watts per reference V620 (not total host power).";
    };
    expectedCount = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Number of reference V620s that must all accept the cap.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = builtins.elem (toString kernelPatch)
        (map toString config.boot.kernelPackages.kernel.patches);
      message = "The selected kernel must include the V620 power-cap patch; check argsOverride.kernelPatches.";
    }];

    boot.kernelPatches = [{
      name = "amdgpu-v620-powercap-min-120w";
      patch = kernelPatch;
    }];

    systemd.services.v620-powercap = {
      description = "Apply and verify ${toString cfg.watts} W PPT caps on all V620s";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${./amd-v620-powercap.py} --watts ${toString cfg.watts} --expected-count ${toString cfg.expectedCount}";
        TimeoutStartSec = 70;
      };
    };

    # GPU recovery/resume can restore the firmware default. Recheck without
    # rewriting an already-correct cap; use a timer so failures stay visible.
    systemd.timers.v620-powercap = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitInactiveSec = "30s";
        AccuracySec = "1s";
      };
    };
  };
}
