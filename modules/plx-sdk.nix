{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  # SDK 8.23 knows x86 and arm64, but not the fleet's riscv64 targets.
  supported = builtins.elem pkgs.stdenv.hostPlatform.system [
    "x86_64-linux"
    "aarch64-linux"
  ];

  plxSvc = config.boot.kernelPackages.callPackage ../packages/plx-sdk/svc.nix {
    src = inputs.plx-sdk;
  };
  plxCm = pkgs.callPackage ../packages/plx-sdk/plxcm.nix {
    src = inputs.plx-sdk;
  };
in {
  config = lib.mkIf supported {
    # Make the driver available to modprobe without binding it automatically.
    # PlxSvc is a broad service/debug driver, so loading remains deliberate.
    boot.extraModulePackages = [plxSvc];

    environment.systemPackages = [plxCm];
  };
}
