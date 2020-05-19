{ pkgs }:

rec {
  bl1 = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/hardkernel/u-boot/odroidc-v2011.03/sd_fuse/bl1.bin.hardkernel";
    sha256 = "1l4mfykqn09mjsmkvrmn5i8yyq6b84qmarwq77ycgrdpggq9a1b7";
  };
  uboot = pkgs.pkgsCross.armv7l-hf-multiplatform.callPackage ./uboot.nix { };
  write-sd = pkgs.writeScriptBin "write-sd" ''
    dd conv=notrunc if=${bl1} of=$1 bs=1 count=442
    dd conv=notrunc if=${bl1} of=$1 bs=512 skip=1 seek=1
    dd conv=notrunc if=${uboot}/u-boot.bin of=$1 bs=512 seek=64
  '';

  /* sudo mkimage -A arm -O linux -T kernel -C none -a 0x00208000 -e 0x00208000 -n "Linux kernel" -d mnt2/boot/nixos/w2qdinywxa8s3xldlr8yz81ynwr8yv2w-linux-5.7-rc5-zImage uImage */
  /* sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n uInitrd -d initrd uInitrd*/
}
