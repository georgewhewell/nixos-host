{ config, pkgs, lib, ... }:

{
  networking.hostName = "orangepi-pc2";


  boot.kernelPackages = pkgs.linuxPackages_allwinner;
  boot.kernelPatches =
  [{
    # Disable regular kernel media modules since dependencies will
    # collide with other v4l2 from tbs modules
    name = "disable media";
    patch = null;
    extraConfig = ''
      MEDIA_SUPPORT n
      PCI n
      DRM n
      FS_XFS n
      FS_UDF n
      FS_UBIFS n
    '';
  }
  {
    # FRAME_VECTOR is needed by videobuf2
    # but wont get selected since we disabled above
    # reenable it manually
    name = "frame vector";
    patch = ../../../services/frame-vector.patch;
    extraConfig = ''
      FRAME_VECTOR y
    '';
  }] ++ (
    let badPatches = [
      "general-add-overlay-compilation-support"
      "xxx-add-nanopi-r1-and-duo2"
      "general-enable-kernel-dtbs-symbol-generation"
      /* "0001-Revert-leds"
      "0002-Add-leds"
      "board-pine64-add-spi-flash"

      "board-pine-h6" */
      "check"
      "patch-5.8"
      "AC200"
      "tanix"
      /* "ruart-alias" */

      "update-correct-h3-h5-thermal-zones"
      "sun8i-h3-add-overclock-overlays"
      "sun50i-h5-add-gpio-regulator-overclock-overlays"
      "0007-mmc-sunxi-add-support-for-the-MMC-controller"
      "board-h3-nanopi-neo-air"

      "general-fix-builddeb-packaging"
      "general-sunxi-overlays"
      "wifi-"
      "disable-debug-rtl8189fs"
      "disable-debug-rtl8723ds"
      "8723cs"
      "rtl8723bs"

      ".patch.1"
      "-DISABLED"
      ".disabled"
      "-disabled"
      ".patch_broken"
    ];
  in
    (builtins.filter ({ name, ... }: lib.all
      (badPatch: ! lib.hasInfix badPatch name) badPatches
    )
    (lib.mapAttrsToList (name: _: {
        name = "${name}";
        patch = "${pkgs.sources.armbian}/patch/kernel/sunxi-current/${name}";
    })
    (builtins.readDir "${pkgs.sources.armbian}/patch/kernel/sunxi-current"))));


  imports = [
    ../common.nix
  ];
}
