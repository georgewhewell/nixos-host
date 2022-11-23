{ config, lib, pkgs, ... }:

{
  imports = [ ../profiles/nbd-overlayfs.nix ];
  options = { };

  config = {

    system.build.usb = {
      loader =
        let
          netboot-binaries = pkgs.symlinkJoin {
            name = "netboot";
            paths = with config.system.build; [
              initialRamdisk
              kernel
              pkgs.boot-scripts.nanopi-m3.uboot

            ];
            postBuild = ''
              ${pkgs.buildPackages.ubootTools}/bin/mkimage -A arm64 -O linux -T ramdisk -C none -d $out/initrd $out/uInitrd
              ${pkgs.buildPackages.ubootTools}/bin/mkimage -A arm64 -T kernel -C none -d $out/Image $out/uImage
              ${pkgs.buildPackages.boot-scripts.nanopi-m3.nanopi-load}/bin/nanopi-load -b USB -o $out/u-boot-nsih.bin $out/u-boot.bin 0x00000000
            '';
          };
          storeRoot = pkgs.closureInfo { rootPaths = [ config.system.build.toplevel ]; };
          rootfsImage = pkgs.callPackage <nixpkgs/nixos/lib/make-ext4-fs.nix> ({
            storePaths = [ config.system.build.toplevel pkgs.stdenv ];
            compressImage = false;
            volumeLabel = "NIXOS_SD";
          });
          bootEnv = pkgs.writeText "bootenv.txt" ''
            #=uEnv
            bootargs=init=${config.system.build.toplevel}/init rootImage=${rootfsImage} storeRoot=${storeRoot} ${toString config.boot.kernelParams}
            udown_kernel=udown 0x41000000
            udown_initrd=udown 0x45000000
            udown_dtb=udown 0x4c000000
            initrd_high=0xffffffff
            bootcmd2=echo "Starting downloads"; \
              run udown_kernel; \
              run udown_initrd; \
              run udown_dtb; \
              echo "Booting kernel.." \
              booti 0x41000000 0x45000000 0x4c000000
          '';
          nanopi-load-native = pkgs.buildPackages.boot-scripts.nanopi-m3.nanopi-load;
        in
        pkgs.writeScriptBin "boot.sh" ''
          echo "uploading bl1"
          ${nanopi-load-native}/bin/nanopi-load -f -x \
            ${pkgs.boot-scripts.nanopi-m3.bl1-usb}

          sleep 1
          echo "uploading uboot"
          ${nanopi-load-native}/bin/nanopi-load -f \
            ${netboot-binaries}/u-boot.bin 0x43bffe00

          sleep 2
          echo "uploading environment"
          ${nanopi-load-native}/bin/nanopi-load \
            ${bootEnv} 0

          sleep 1
          echo "uploading kernl"
          ${nanopi-load-native}/bin/nanopi-load \
            ${netboot-binaries}/Image 0

          sleep 1
          echo "uploading initrd"
          ${nanopi-load-native}/bin/nanopi-load \
            ${netboot-binaries}/uInitrd 0

          sleep 1
          echo "uploading dtb"
          ${nanopi-load-native}/bin/nanopi-load \
            ${netboot-binaries}/dtbs/nexell/nanopim3.dtb 0
        '';
    };

  };

}
