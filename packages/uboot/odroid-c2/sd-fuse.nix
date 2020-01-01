{ pkgs, fip_create, odroid-c2-bl1, meson-tools }:

let
  uboot-wrapped = pkgs.runCommand "u-boot.img" { } ''
    # Ref: http://git.denx.de/?p=u-boot.git;a=blob_plain;f=board/amlogic/odroid-c2/README;hb=HEAD
    export HKDIR=${fip_create.src}

    echo "Creating FIP"
    ${fip_create}/bin/fip_create \
      --bl30  $HKDIR/fip/gxb/bl30.bin \
      --bl301 $HKDIR/fip/gxb/bl301.bin \
      --bl31  $HKDIR/fip/gxb/bl31.bin \
      --bl33  ${pkgs.pkgsCross.aarch64-multiplatform.callPackage ./uboot.nix {}}/u-boot.bin \
      --dump \
      fip.bin

    echo "Inserting bl2"
    cat $HKDIR/fip/gxb/bl2.package fip.bin > boot_new.bin

    echo "Wrapping u-boot"
    ${meson-tools}/bin/amlbootsig boot_new.bin $out
'';
in pkgs.writeScript "odroid-c2-sd-fuse.sh" ''
  echo writing to: $1
  dd if=${odroid-c2-bl1.default} of=$1 conv=notrunc bs=1 count=442
  dd if=${odroid-c2-bl1.default} of=$1 conv=notrunc bs=512 skip=1 seek=1
  dd if=${uboot-wrapped} of=$1 conv=notrunc bs=512 skip=96 seek=97
''
