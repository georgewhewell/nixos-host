{ config, ... }:

{
  imports = [
    ../common-arm.nix
    ../../services/buildfarm.nix
    <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-armv7l-multiplatform.nix>
  ];
}
