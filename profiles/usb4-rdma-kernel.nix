{
  pkgs,
  lib,
  inputs,
  ...
}: let
  usb4KernelPatches = inputs.usb4-rdma.legacyPackages.${pkgs.stdenv.hostPlatform.system}.usb4KernelPatches;
  torvaldsLinuxSrc = pkgs.fetchFromGitHub {
    owner = "torvalds";
    repo = "linux";
    rev = "v7.1-rc1";
    hash = "sha256-88uBvJ2fZEWUAyMJZRNEFBZZPWaCp5O+KhTGa8u4EQw=";
  };
  linuxPackagesUsb4 = pkgs.linuxPackages_testing.extend (self: super: {
    kernel = super.kernel.override {
      argsOverride = {
        src = torvaldsLinuxSrc;
        version = "7.1-rc1";
        modDirVersion = "7.1.0-rc1";
      };
      kernelPatches = (super.kernel.kernelPatches or []) ++ usb4KernelPatches;
      structuredExtraConfig = with lib.kernel; {
        # Torvalds v7.1-rc1 is ahead of this nixpkgs pin; drop stale
        # common-config entries instead of hiding them with ignoreConfigErrors.
        AX25 = lib.mkForce unset;
        CRC32_SELFTEST = lib.mkForce unset;
        CRYPTO_TEST = lib.mkForce unset;
        DMABUF_MOVE_NOTIFY = lib.mkForce unset;
        EXT3_FS_POSIX_ACL = lib.mkForce unset;
        EXT3_FS_SECURITY = lib.mkForce unset;
        GLOB_SELFTEST = lib.mkForce unset;
        HAMRADIO = lib.mkForce unset;
        POWER_RESET_GPIO = lib.mkForce unset;
        POWER_RESET_GPIO_RESTART = lib.mkForce unset;
        PREEMPT_VOLUNTARY = lib.mkForce unset;
        USB4_CONFIGFS = module;
        USB4_DEBUGFS_WRITE = yes;
        USB4_STREAM = module;
        XEN_SAVE_RESTORE = lib.mkForce unset;

        FB_HYPERV = lib.mkForce unset;
        HIPPI = lib.mkForce unset;
        NFS_V4_1 = lib.mkForce unset;
      };
    };
  });
in {
  imports = [
    inputs.usb4-rdma.nixosModules.thunderbolt-ibverbs
  ];

  boot.kernelPackages = lib.mkOverride 900 linuxPackagesUsb4;

  hardware.thunderbolt-ibverbs.enable = true;
}
