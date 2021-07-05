{ pkgs, lib }:
let
  defConfigs = [
    "orangepi_pc2_defconfig"
    "orangepi_prime_defconfig"
    "nanopi_neo2_defconfig"
    "pine64_plus_defconfig"
  ];
  buildAllwinnerUboot = (defconfig:
    pkgs.pkgsCross.aarch64-multiplatform.buildUBoot {
      inherit defconfig;
      extraMeta.platforms = [ "aarch64-linux" ];
      BL31 = "${pkgs.pkgsCross.aarch64-multiplatform.armTrustedFirmwareAllwinner}/bl31.bin";
      filesToInstall = [ "u-boot-sunxi-with-spl.bin" ];
      extraPatches =
        let badPatches = [
            "-DISABLED"
            ".disabled"
            "-disabled"
            ".patch_broken"
            "disable-de2"
            "beelink"
            "nanopi-r1"
            "add-orangepi-zeroplus2_h3"
            "board_lime2"
            "board_olimex-som-a20"
            "board_pine64so"
            "branch_default"
          ];
        in
          (builtins.filter ( name: lib.all
            (badPatch: ! lib.hasInfix badPatch name) badPatches
          )
          (lib.mapAttrsToList (name: _: "${pkgs.sources.armbian}/patch/u-boot/u-boot-sunxi/${name}")
          (builtins.readDir "${pkgs.sources.armbian}/patch/u-boot/u-boot-sunxi")));
    }
  );
in
pkgs.lib.genAttrs defConfigs (defconfig: pkgs.writeScript "sd-fuse" ''
  echo "writing to $1"
  dd if=${buildAllwinnerUboot defconfig}/u-boot-sunxi-with-spl.bin of=$1 bs=1024 seek=8
'')
