{ config, lib, pkgs, ... }:

with lib;

let
    cfg = config.nbd-boot;
in
  {
      options = {

        nbd-boot.enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Enable NBD partitions etc
          '';
        };

      };

      config = mkIf cfg.enable {

      boot.loader.grub.enable = false;

      /*
      fileSystems."/" = {
        fsType = "tmpfs";
        options = [ "mode=0755" ];
        neededForBoot = true;
        };
        */

      fileSystems."/nix/.ro-store" =
        { fsType = "squashfs";
          device = "/dev/nbd0";
          options = [];
          neededForBoot = true;
        };

      fileSystems."/nix/.rw-store" =
        { fsType = "ext2";
          device = "/dev/nbd1";
          options = [ "noatime" "nodiratime" ];
          neededForBoot = true;
        };

      fileSystems."/nix/store" =
        { fsType = "overlay";
          device = "overlay";
          options = [
            "rw" "relatime"
            "default_permissions"
            "lowerdir=/mnt-root/nix/.ro-store"
            "workdir=/mnt-root/nix/.rw-store/work"
            "upperdir=/mnt-root/nix/.rw-store/store"
          ];
          noCheck = true;
          neededForBoot = true;
        };

      fileSystems."/tmp" = {
        device = "/nix/.rw-store/tmp";
        options = [ "bind" ];
        noCheck = true;
      };

      boot.initrd.availableKernelModules = [
        "squashfs" "overlay" "crc32_arm_ce" ];

      boot.initrd.network.enable = true;

      boot.initrd.nbd = {
        enable = true;

        devices = {
          nbd0 = {
            name = "nixos";
            hostname = "ADDRESS";
            port = "PORT";
          };
          nbd1 = {
            name = "scratch";
            hostname = "ADDRESS";
            port = "PORT";
          };
        };

        postCommands = ''
          echo "Preparing scratch mountpoints"
          ${pkgs.e2fsprogs}/bin/mkfs.ext2 /dev/nbd1

          mkdir /scratch
          mount /dev/nbd1 /scratch
          mkdir -p /scratch/store
          mkdir -p /scratch/work
          mkdir -p /scratch/tmp
          echo "Created mountpoints, unmounting scratch"
          sync
          umount /scratch
        '';
      };

      # Closures to be copied to the Nix store, namely the init
      # script and the top-level system configuration directory.
      netboot.storeContents = [ config.system.build.toplevel ];

      # Create the squashfs image that contains the Nix store.
      system.build.squashfsStore = pkgs: import <nixpkgs/nixos/lib/make-squashfs.nix> {
        inherit (pkgs) stdenv squashfsTools closureInfo;
        storeContents = config.netboot.storeContents;
      };

      boot.loader.timeout = 10;
      boot.postBootCommands = ''
        # After booting, register the contents of the Nix store
        # in the Nix database in the tmpfs.
        ${config.nix.package}/bin/nix-store --load-db < /nix/store/nix-path-registration

        # nixos-rebuild also requires a "system" profile and an
        # /etc/NIXOS tag.
        touch /etc/NIXOS
        ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
      '';    
    };
} 
