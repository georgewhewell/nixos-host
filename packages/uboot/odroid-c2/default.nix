{ callPackage }:

rec {

  odroid-c2-bl1 = callPackage ./bl1.nix { };
  fip_create = callPackage ./fip-create.nix { };
  meson-tools = callPackage ./meson-tools.nix { };
  ubootOdroidC2 = callPackage ./uboot.nix { };
  sd-fuse = callPackage ./sd-fuse.nix { inherit fip_create odroid-c2-bl1 meson-tools; };

}
