{ config, pkgs, ... }:

{

  imports = [
    ../common-arm.nix
    ../../services/buildfarm.nix
    <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-aarch64.nix>
  ];

}
