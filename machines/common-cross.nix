{ config, pkgs, lib, ... }: {

  nixpkgs.overlays = [
    (self: super: {
      /*  */
    })
  ];

  # (Failing build in a dep to be investigated)
  security.polkit.enable = lib.mkForce false;
  services.udisks2.enable = lib.mkForce false;

  # cifs-utils fails to cross-compile
  # Let's simplify this by removing all unneeded filesystems from the image.
  boot.supportedFilesystems = lib.mkForce [ "vfat" ];

}
