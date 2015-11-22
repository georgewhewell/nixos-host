{ config, lib, pkgs, ... }:

{
  # Save this file!
  system.copySystemConfiguration = true;

  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "16.03";

  nix.binaryCachePublicKeys = [
"hydra.nixos.org-1:CNHJZBh9K4tP3EKF6FkkgeVYsS3ohTl+oS0Qa8bezVs=" ];
}
