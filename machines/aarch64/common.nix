{ config, pkgs, ... }:

{

  imports = [
    ../common-arm.nix
    <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-aarch64.nix>
  ];

}
