{ config, lib, ... }:

{

  # libp11 fails to compile
  security.rngd.enable = lib.mkForce false;
  security.polkit.enable = lib.mkForce false;

  imports = [
    ../common-arm.nix
    ../../services/buildfarm.nix
    <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-armv7l-multiplatform.nix>
  ];
}
