{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.netboot;
in
{
  options = {

    netboot.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable NBD partitions etc
      '';
    };

    netboot.storeContents = mkOption {
      example = literalExample "[ pkgs.stdenv ]";
      description = ''
        This option lists additional derivations to be included in the
        Nix store in the generated netboot image.
      '';
    };

    netboot.bootloader = mkOption {
      example = literalExample "pkgs.UBootOrangePiZero";
    };

  };

  config = mkIf cfg.enable {

    boot.loader.grub.enable = false;

    system.build.bootloader = cfg.bootloader;

    fileSystems."/" = {
      fsType = "tmpfs";
      options = [ "mode=0755" ];
      neededForBoot = true;
    };

    fileSystems."/nix/store" =
      {
        device = "192.168.23.43:/store";
        fsType = "nfs";
        options = [ "vers=4" "ro" "rsize=32768" "wsize=32768" "nconnect=4" ];
        neededForBoot = true;
      };

    boot.initrd.availableKernelModules = [ "nfsv4" ];

    usb-gadget = {
      enable = true;
      initrdDHCP = true;
    };
    /* boot.initrd.network = {
      enable = true;
      flushBeforeStage2 = false;
    }; */
  };
}
