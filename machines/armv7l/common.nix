{ config, ... }:

{
  imports = [
    ../common-arm.nix
    <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-armv7l-multiplatform.nix>
  ];
}
