{ config, pkgs, lib, ... }:

{

  networking.hostName = "odroid-c1";

  imports = [
    ../common.nix
  ];

  boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor (pkgs.linux_testing.override {
    argsOverride = rec {
      src = pkgs.fetchFromGitHub {
        owner = "xdarklight";
        repo = "linux";
        rev = "meson-mx-integration-5.8-20200520";
        sha256 = "0iyhvq5l536a501m0xmj3s84xz50p0q4z3kyj4i57f43g0bflxa0";
      };
      version = "5.7-rc6";
      modDirVersion = "5.7.0-rc6";
    };
  }));

  boot.kernelPatches = [{
    name = "broken-extcon";
    patch = null;
    extraConfig = ''
      USB_CONN_EXTCON n
      MESON_MX_AO_ARC_FIRMWARE n
    '';
  }]; 

  /*
  system.build.installBootLoader = ''
    ${pkgs.ubootTools}/bin/mkimage -A arm -O linux -T kernel -C none -a 0x00208000 -e 0x00208000 -n "Linux kernel" -d ${config.system.build.kernel}/zImage boot/uImage
    ${pkgs.ubootTools}/bin/mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n uInitrd -d ${config.system.build.initialRamdisk}/initrd boot/uInitrd
    '';
  */

  sdImage.populateFirmwareCommands = let
    bootini = pkgs.writeText "boot.ini" ''
      ODROIDC-UBOOT-CONFIG
      setenv condev "console=ttyS0,115200n8"
      setenv bootargs "systemConfig=${config.system.build.toplevel} init=${config.system.build.toplevel}/init ${toString config.system.build.toplevel.kernelParams}"

      fatload mmc 0:1 0x21000000 uImage
      fatload mmc 0:1 0x22000000 uInitrd
      fatload mmc 0:1 0x21800000 meson8b-odroidc1.dtb

      fdt rm /mesonstream; fdt rm /vdec; fdt rm /ppmgr
      fdt rm /mesonfb

      bootm 0x21000000 0x22000000 0x21800000
    '';
  in ''
    ls -la firmware
    rm -rf firmware/*
    ${pkgs.buildPackages.ubootTools}/bin/mkimage -A arm -O linux -T kernel -C none -a 0x00208000 -e 0x00208000 -n "Linux kernel" -d ${config.system.build.kernel}/zImage firmware/uImage
    ${pkgs.buildPackages.ubootTools}/bin/mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n uInitrd -d ${config.system.build.initialRamdisk}/initrd firmware/uInitrd
    cp ${config.system.build.toplevel}/dtbs/meson8b-odroidc1.dtb firmware/meson8b-odroidc1.dtb
    cp ${bootini} firmware/boot.ini
  '';
}
