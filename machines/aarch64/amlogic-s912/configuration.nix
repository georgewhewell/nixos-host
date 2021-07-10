{ config, pkgs, lib, ... }:

{
  networking.hostName = "amlogic-s912";
  boot.kernelParams = [ "cma=786M" ];

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_amlogic;
  hardware.firmware = with pkgs; [ meson-firmware armbian-firmware ];

  # make /dev/dri0 be panfrost?
  boot.initrd.availableKernelModules = [ "panfrost" ];

    /*
  ] ++
  (  let badPatches = [
      "amlogic-00"
      "v2-drm-panfrost-Use-kvfree"
      "arm64-dts-meson-add-missing-gxl"
      "ASoC-soc-pcm-dpcm-fix-playback-capture-checks"
      "arm64-dts-meson-misc-fixups-for-w400"
      "arm64-dts-meson-fix-mmc0-tuning"
#      "0061"
#      "0073"
#      "0094"
#      "0106"
    ];
  in
    (builtins.filter ({ name, ... }: lib.all
      (badPatch: ! lib.hasInfix badPatch name) badPatches
    )
    (lib.mapAttrsToList (name: _: {
        name = "${name}";
        patch = "${pkgs.sources."LibreELEC.tv"}/projects/Amlogic/patches/linux/${name}";
    })
    (builtins.readDir "${pkgs.sources."LibreELEC.tv"}/projects/Amlogic/patches/linux")))); */

  imports = [
    ../common.nix
    ../../../profiles/nas-mounts.nix
    ../../../profiles/tvbox-gbm.nix
  ];
}
