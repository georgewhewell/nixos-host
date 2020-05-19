  { config, pkgs, lib, ... }: {

    nixpkgs.overlays = [(self: super: {
      # Does not cross-compile...
      alsa-firmware = pkgs.runCommandNoCC "neutered-firmware" {} "mkdir -p $out";

      # needs a bunch of python stuff which does not CC
      crda = pkgs.runCommandNoCC "crda" {} "mkdir -p $out";
    })];

    # (Failing build in a dep to be investigated)
    security.rngd.enable = lib.mkForce false;
    security.polkit.enable = lib.mkForce false;
    services.udisks2.enable = lib.mkForce false;

    # cifs-utils fails to cross-compile
    # Let's simplify this by removing all unneeded filesystems from the image.
    boot.supportedFilesystems = lib.mkForce [ "vfat" ];

  }
