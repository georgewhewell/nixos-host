{ pkgs }:
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
    }
  );
in
pkgs.lib.genAttrs defConfigs (defconfig: pkgs.writeScript "sd-fuse" ''
  echo "writing to $1"
  dd if=${buildAllwinnerUboot defconfig}/u-boot-sunxi-with-spl.bin of=$1 bs=1024 seek=8
'')
