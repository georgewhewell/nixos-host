{
  lib,
  fetchFromGitHub,
  buildLinux,
  src,
  pkgs,
  ...
} @ args: let
  kernelVersion = "5.10.110";
  vendorVersion = "";
  version = "${kernelVersion}${vendorVersion}";
in
  buildLinux (args
    // {
      inherit version;

      # https://github.com/radxa/build/blob/428769f2ab689de27927af4bc8e7a9941677c366/board_configs.sh#L304
      defconfig = "rockchip_linux_defconfig";

      # branchVersion needs to be x.y
      extraMeta.branch = lib.versions.majorMinor version;
      # NOTE: The NixOS infra automatically enables all unspecified modules as `=m`.
      #       This is why there's a lot of crap to disable.
      structuredExtraConfig = with lib.kernel; {
        # Not needed, and implementation iffy / does not build / used for testing
        MALI_KUTF = no;
        MALI_IRQ_LATENCY = no;
        # Build fails, "legacy/webcam.c" we don't need no legacy stuff.
        USB_G_WEBCAM = no;
        # Poor quality drivers, bad implementation, not needed
        WL_ROCKCHIP = no; # A lot of badness
        RK628_EFUSE = no; # Not needed, used to "dump specified values"
        # Used on other rockchip platforms
        ROCKCHIP_DVBM = no;
        RK_FLASH = no;
        PCIEASPM_EXT = no;
        ROCKCHIP_IOMUX = no;
        RSI_91X = no;
        RSI_SDIO = no;
        RSI_USB = no;
        WLAN_VENDOR_BROADCOM = no;

        # Driver conflicts with the mainline ones
        # > error: the following would cause module name conflict:
        COMPASS_AK8975 = no;
        LS_CM3232 = no;
        GS_DMT10 = no;
        GS_KXTJ9 = no;
        GS_MC3230 = no;
        GS_MMA7660 = no;
        GS_MMA8452 = no;

        # This is not a good console...
        # FIQ_DEBUGGER = no;
        # TODO: Fix 8250 console not binding as a console

        # from vendor config
        #DRM_DP = no; # ????? does not build with it disabled ffs
        DRM_DEBUG_SELFTEST = no;

        # Ugh...
        ROCKCHIP_DEBUG = no;
        RK_CONSOLE_THREAD = no;
      };

      inherit src;
      kernelPatches = [
          pkgs.kernelPatches.bridge_stp_helper
          pkgs.kernelPatches.request_key_helper
        ] ++ builtins.map (patch: { inherit patch; }) [
          ./0000-Set-RK3588-FIQ-at-115200-bauds.patch
          ./0001-Ignore-implementation-defects-warned-by-newer-GCC.patch
          ./0002-rk630phy-Fix-implementation.patch
          ./0003-usb-gadget-legacy-webcam-Fix-implementation.patch
          ./0004-revert-commit-f7382476af9d5e3d94bacc769bbf23d5fafd5cdb.patch
          ./0005-arm64-dts-rk3588-rock-5b-Use-serial-instead-of-FIQ.patch
          ./0006-arm64-boot-dts-rk3588-rock-5b-Enable-sfc-and-SPI-Flash.patch
          ./0007-rock-5b-Configure-FIQ-debugger-as-115200.patch
          ./0008-rock-5b-disable-uart2-wont-bind-as-a-console.patch
        ];

    }
    // (args.argsOverride or {}))
