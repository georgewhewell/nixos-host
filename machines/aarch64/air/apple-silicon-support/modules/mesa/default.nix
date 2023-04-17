{ config, pkgs, lib, ... }:
{
  config = let
    isMode = mode: (config.hardware.asahi.useExperimentalGPUDriver
        && config.hardware.asahi.experimentalGPUInstallMode == mode);
  in lib.mkMerge [
    (lib.mkIf config.hardware.asahi.useExperimentalGPUDriver {

      # install the drivers
      hardware.opengl.package = pkgs.mesa-asahi-edge.drivers;

      # required for GPU kernel driver
      hardware.asahi.addEdgeKernelConfig = true;
    })
    (lib.mkIf (isMode "replace") {
      # replace the Mesa linked into system packages with the Asahi version
      # without rebuilding them to avoid rebuilding the world.
      system.replaceRuntimeDependencies = [
        { original = pkgs.mesa;
          replacement = pkgs.mesa-asahi-edge;
        }
      ];
    })
    (lib.mkIf (isMode "overlay") {
      # replace the Mesa used in Nixpkgs with the Asahi version using an overlay,
      # which requires rebuilding the world but ensures it is done faithfully
      # (and in a way compatible with pure evaluation)
      nixpkgs.overlays = [
        (final: prev: {
          mesa = final.mesa-asahi-edge;
        })
      ];
    })
  ];

  options.hardware.asahi.useExperimentalGPUDriver = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Use the experimental Asahi Mesa GPU driver.

      Do not report issues using this driver under NixOS to the Asahi project.
    '';
  };

  options.hardware.asahi.experimentalGPUInstallMode = lib.mkOption {
    type = lib.types.enum [ "driver" "replace" "overlay" ];
    default = "replace";
    description = ''
      Mode to use to install the experimental GPU driver into the system.

      driver: install only as a driver, do not replace system Mesa.
        Causes issues with certain programs like Plasma Wayland.

      replace (default): use replaceRuntimeDependencies to replace system Mesa with Asahi Mesa.
        Does not work in pure evaluation context (i.e. in flakes by default).

      overlay: overlay system Mesa with Asahi Mesa
        Requires rebuilding the world.
    '';
  };
}
