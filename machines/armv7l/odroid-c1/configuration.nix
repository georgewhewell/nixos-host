{ config, pkgs, lib, ... }:

{

  networking.hostName = "odroid-c1";

  imports = [
    ../common.nix
  ];

  boot.kernelParams = [ "boot.shell_on_fail" "console=ttyAML0,115200" "earlyprintk=serial,ttyAML0,115200" ];
  boot.kernelPackages = lib.mkOverride 1 pkgs.linuxPackages_meson_mx;

  boot.initrd.kernelModules = [ "meson-mx-sdhc" "r8152" ];

  systemd.services."getty@tty1".enable = false;

  services.consul.enable = lib.mkForce false;

  sdImage.populateFirmwareCommands =
    let
      bootini = pkgs.writeText "boot.ini" ''
        ODROIDC-UBOOT-CONFIG
        setenv condev "console=ttyS0,115200n8"
        setenv bootargs "systemConfig=${config.system.build.toplevel} init=${config.system.build.toplevel}/init ${toString config.system.build.toplevel.kernelParams}"

        fatload mmc 0:1 0x21000000 uImage
        fatload mmc 0:1 0x22000000 uInitrd
        fatload mmc 0:1 0x21800000 meson8b-odroidc1.dtb

        bootm 0x21000000 0x22000000 0x21800000
      '';
    in
    ''
      # delete rpi crap
      rm -rf firmware/*
      ${pkgs.buildPackages.ubootTools}/bin/mkimage -A arm -O linux -T kernel -C none -a 0x00208000 -e 0x00208000 -n "Linux kernel" -d ${config.system.build.kernel}/zImage firmware/uImage
      ${pkgs.buildPackages.ubootTools}/bin/mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n uInitrd -d ${config.system.build.initialRamdisk}/initrd firmware/uInitrd
      cp ${config.system.build.toplevel}/dtbs/meson8b-odroidc1.dtb firmware/meson8b-odroidc1.dtb
      cp ${bootini} firmware/boot.ini
    '';
}
