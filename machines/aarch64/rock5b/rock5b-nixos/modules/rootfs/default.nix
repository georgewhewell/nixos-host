{ config
, lib
, pkgs
, modulesPath
, nixpkgsPath
, ...
}: {
  imports = [ "${modulesPath}/installer/sd-card/sd-image-aarch64-installer.nix" ];

  config = {
    fileSystems = lib.mkForce {
      "/" = { label = "NIXOS_ROOTFS"; };
    };
    boot.supportedFilesystems = [ "vfat" ];
    # Builds an (opinionated) rootfs image.
    # NOTE: *only* the rootfs.
    #       it is expected the end-user will assemble the image as they need.
    system.build.rootfsImage =
      pkgs.callPackage
        (
          { callPackage
          , lib
          , populateCommands
          ,
          }:
          callPackage "${nixpkgsPath}/nixos/lib/make-ext4-fs.nix" ({
            inherit (config.sdImage) storePaths;
            compressImage = false;
            populateImageCommands = populateCommands;
            volumeLabel = config.fileSystems."/".label;
          }
          // lib.optionalAttrs (config.sdImage.rootPartitionUUID != null) {
            uuid = config.sdImage.rootPartitionUUID;
          })
        )
        {
          populateCommands = ''
            mkdir -p ./files/boot
            ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
          '';
        };
  };
}
