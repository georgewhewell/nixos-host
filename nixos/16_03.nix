{ config, lib, pkgs, ... }:

{
  # Save this file!
  system.copySystemConfiguration = true;

  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "16.03";

  nix = {
    buildCores = 0;
    daemonIONiceLevel = 7;
    daemonNiceLevel = 10;
    useChroot = true;
    extraOptions = ''
      auto-optimise-store = true
    '';
    trustedBinaryCaches = [
      https://cache.nixos.org
      https://hydra.nixos.org
    ];
    binaryCachePublicKeys = [
      "hydra.nixos.org-1:CNHJZBh9K4tP3EKF6FkkgeVYsS3ohTl+oS0Qa8bezVs="
    ];
  };
  
}
