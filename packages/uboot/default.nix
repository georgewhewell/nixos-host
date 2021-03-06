{ callPackage }: {

  allwinner = callPackage ./allwinner { };
  allwinner-armv7l = callPackage ./aw-arm7.nix { };
  odroid-c2 = callPackage ./odroid-c2 { };
  rock64 = callPackage ./rock64 { };
  sapphire = callPackage ./rk3399 { };

  nanopi-m3-uboot = callPackage ./nanopi-m3/uboot.nix { };
  nanopi-m3 = callPackage ./nanopi-m3 { };

  odroid-hc1 = callPackage ./odroid-hc1 { };
  odroid-c1 = callPackage ./odroid-c1 { };

  amlogic-s912 = callPackage ./s912 { };

}
