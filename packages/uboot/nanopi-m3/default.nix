{ pkgs }:

rec {
  uboot = pkgs.pkgsCross.aarch64-multiplatform.callPackage ./uboot.nix { };

  bl1-sd = pkgs.pkgsCross.aarch64-multiplatform.callPackage ./bl1.nix { };
  bl1-usb = pkgs.pkgsCross.aarch64-multiplatform.callPackage ./bl1.nix { usbBoot = true; };

  nanopi-load = pkgs.callPackage ./nanopi-load.nix { };

  uboot-sd = pkgs.runCommandNoCC "uboot-sd"
    { } ''
    ${nanopi-load}/bin/nanopi-load \
      -f \
      -b SD \
      -o $out \
      ${uboot}/u-boot.bin 0x43bffe00
  '';

  write-sd = pkgs.writeScriptBin "write-sd" ''
    dd conv=notrunc if=${bl1-sd} of=$1 seek=1
    dd conv=notrunc if=${uboot-sd} of=$1 seek=64
  '';

}
