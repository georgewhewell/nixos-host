{ pkgs }:

  buildAllwinnerUboot = (defconfig:
    pkgs.pkgsCross.armv7l-hf-multiplatform.buildUBoot {
      inherit defconfig;
      extraMeta.platforms = [ "armv7l-linux" ];
      filesToInstall = [ "u-boot-sunxi-with-spl.bin" ];
    });
in pkgs.writeScript "sd-fuse" ''
  echo "writing to $1"
  dd if=${buildAllwinnerUboot defconfig}/u-boot-sunxi-with-spl.bin conv=notrunc of=$1 bs=1024 seek=8
'')
