{ pkgs }:

let

xpkgs = pkgs.pkgsCross.armv7l-hf-multiplatform;
in pkgs.writeScript "sd-fuse" ''
  echo "writing to $1"
  sh ${xpkgs.odroid-xu3-bootloader}/bin/sd_fuse-xu3 $1
''
