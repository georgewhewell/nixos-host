# Collabora RK3588 hardware enablement kernel
# https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux
#
# Tracks the rockchip-devel branch which carries patches for RK3588 features
# not yet upstream: HDMI 4K@60, video encoding, VP9 decode, DP alt-mode, etc.
#
# Update kernelVersion / modDirVersion when the branch rebases to a new upstream.
# Check with: grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL|EXTRAVERSION)' Makefile
{ lib
, buildLinux
, src
, kernelVersion ? "7.1"
, modDirVersionOverride ? "7.1.0-rc1"
, ...
} @ args:

buildLinux (args // {
  version = kernelVersion;
  modDirVersion = modDirVersionOverride;
  inherit src;

  # The Collabora tree carries its own patches; skip nixpkgs kernel patches
  kernelPatches = [
    {
      name = "rkvenc-vepu580-mpp-service";
      patch = ./rkvenc-vepu580.patch;
      structuredExtraConfig = with lib.kernel; {
        VIDEO_ROCKCHIP_RKVENC = module;
      };
    }
  ];

  # nixpkgs config references options that may not exist in this tree (e.g. XEN_SAVE_RESTORE)
  ignoreConfigErrors = true;

  structuredExtraConfig = with lib.kernel; {
    # Panthor GPU driver (Mali-G610)
    DRM_PANTHOR = module;
  };

  extraMeta = {
    branch = lib.versions.majorMinor kernelVersion;
    description = "Collabora RK3588 hardware enablement kernel";
    platforms = [ "aarch64-linux" ];
  };
} // (args.argsOverride or {}))
