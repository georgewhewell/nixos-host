{ nixpkgs ? <nixpkgs> }:
let
  crossFixes = (import ./machines/common-cross.nix);
  pkgs = (import nixpkgs {
    overlays = [
      (import modules/overlay.nix)
    ];
  }
  );
  lib = pkgs.lib;
  build = system: config: extra:
    (import <nixpkgs/nixos/lib/eval-config.nix> {
      inherit system;
      modules = [ config ] ++ extra;
    }
    );
  buildCross = crossSystem: config: extra:
    let crossBit = { config, lib, ... }: {
      nixpkgs.crossSystem = lib.systems.elaborate {
        config = crossSystem;
      };
    };
    in
    (import <nixpkgs/nixos/lib/eval-config.nix> {
      modules = [ config crossBit crossFixes ] ++ extra;
    }
    );
  x86Machines = (import ./machines/x86 { inherit lib; });
  armMachines = (import ./machines/armv7l { inherit lib; });
  aarch64Machines = (import ./machines/aarch64 { inherit lib; });
  felboot = { pkgs, config, ... }: {
    netboot = {
      enable = true;
    };
  };
  sunxiBoot = config:
    let
      version = "2020.04";
      src = pkgs.fetchurl {
        url = "ftp://ftp.denx.de/pub/u-boot/u-boot-${version}.tar.bz2";
        sha256 = "0wjkasnz87q86hx93inspdjfjsinmxi87bcvj30c773x0fpjlwzy";
      };
      buildAllwinnerUboot = (defconfig:
        pkgs.pkgsCross.armv7l-hf-multiplatform.buildUBoot {
          inherit src version defconfig;
          extraMeta.platforms = [ "armv7l-linux" ];
          filesToInstall = [ "u-boot-sunxi-with-spl.bin" ];
        }
      );
      uboot = buildAllwinnerUboot config.system.build.ubootDefconfig;
      uinitrd = pkgs.runCommandNoCC "uInitrd"
        { } ''
        ${pkgs.ubootTools}/bin/mkimage -A arm -T ramdisk -C none -d ${config.system.build.initialRamdisk}/initrd $out
      '';
      bootEnv = pkgs.writeText "bootenv.txt" ''
        #=uEnv
        bootargs=init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}
        bootcmd=bootz 0x40000000 0x43300000 0x42000000
      '';
    in
    pkgs.writeScriptBin "boot.sh" ''
      set -e

      echo "Checking ver"
      ${pkgs.sunxi-tools}/bin/sunxi-fel ver

      # include stuff
      ${pkgs.sunxi-tools}/bin/sunxi-fel -p \
        uboot ${uboot}/u-boot-sunxi-with-spl.bin \
        write-with-progress 0x40000000 ${config.system.build.kernel}/zImage \
        write-with-progress 0x42000000 ${config.system.build.toplevel}/dtbs/${config.system.build.dtbName}.dtb \
        write-with-progress 0x43300000 ${uinitrd} \
        write-with-progress 0x43100000 ${bootEnv}
    '';
in
{

  tarball =
    pkgs.releaseTools.sourceTarball {
      name = "nixos-configuration";
      src = ./.;
      distPhase = ''
        relname=nixos-configuration
        mkdir ../$relname
        cp -prd . ../$relname
        rm -rf ../$relname/.git ../$relname/svn-revision
        mkdir $out/tarballs
        tar cvfJ $out/tarballs/$relname.tar.xz -C .. $relname
      '';
    };

  x86 = pkgs.lib.mapAttrs
    (name: configuration:
      (build "x86_64-linux" configuration [ ]).config.system.build.toplevel
    )
    x86Machines;

  x86-bootdisk = (build "x86_64-linux" x86Machines.installer [ ]).config.system.build.isoImage;

  armv7l = {
    kernels = pkgs.lib.mapAttrs
      (name: configuration:
        (build "armv7l-linux" configuration [
          <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-armv7l-multiplatform.nix>
        ]
        ).config.system.build.kernel
      )
      armMachines;
    images = pkgs.lib.mapAttrs
      (name: configuration:
        (build "armv7l-linux" configuration [
          <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-armv7l-multiplatform.nix>
        ]
        ).config.system.build.sdImage
      )
      armMachines;
    felboot = pkgs.lib.mapAttrs
      (name: configuration:
        sunxiBoot (build "armv7l-linux" configuration [ felboot ]).config
      )
      armMachines;
  };

  armv7lCross = {
    kernels = pkgs.lib.mapAttrs
      (name: configuration:
        (buildCross "armv7l-unknown-linux-gnueabihf" configuration [
          <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-armv7l-multiplatform.nix>
        ]
        ).config.system.build.kernel
      )
      armMachines;
    images = pkgs.lib.mapAttrs
      (name: configuration:
        (buildCross "armv7l-unknown-linux-gnueabihf" configuration [
          <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-armv7l-multiplatform.nix>
        ]
        ).config.system.build.sdImage
      )
      armMachines;
    felboot = pkgs.lib.mapAttrs
      (name: configuration:
        sunxiBoot (buildCross "armv7l-unknown-linux-gnueabihf" configuration [ felboot ]).config
      )
      armMachines;
  };

  aarch64 = {
    kernels = pkgs.lib.mapAttrs
      (name: configuration:
        (build "aarch64-linux" configuration [
          <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-aarch64.nix>
        ]
        ).config.system.build.kernel
      )
      aarch64Machines;
    images = pkgs.lib.mapAttrs
      (name: configuration:
        (build "aarch64-linux" configuration [
          <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-aarch64.nix>
        ]
        ).config.system.build.sdImage
      )
      aarch64Machines;
  };


  aarch64Cross = {
    kernels = pkgs.lib.mapAttrs
      (name: configuration:
        (buildCross "aarch64-linux" configuration [
          <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-aarch64.nix>
        ]
        ).config.system.build.kernel
      )
      aarch64Machines;
    images = pkgs.lib.mapAttrs
      (name: configuration:
        (buildCross "aarch64-linux" configuration [
          <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-aarch64.nix>
        ]
        ).config.system.build.sdImage
      )
      aarch64Machines;
    felboot = pkgs.lib.mapAttrs
      (name: configuration:
        (buildCross "aarch64-linux" configuration [
          ./modules/nanopi-load.nix
        ]
        ).config.system.build.usb.loader
      )
      aarch64Machines;
  };

}
