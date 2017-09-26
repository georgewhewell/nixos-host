{ config, lib, pkgs, ... }:

{
  nix = {
    buildCores = 0;
    daemonIONiceLevel = 7;
    daemonNiceLevel = 10;
    nixPath = [
        "nixpkgs=/etc/nixos/nixpkgs"
        "nixos-config=/etc/nixos/configuration.nix"
    ];
    binaryCaches = [
      https://cache.nixos.org
    ];
    binaryCachePublicKeys = [
      "hydra.nixos.org-1:CNHJZBh9K4tP3EKF6FkkgeVYsS3ohTl+oS0Qa8bezVs="
    ];
    extraOptions = ''
      auto-optimise-store = true
    '';
  };

  nixpkgs.config = {
    allowUnfree = true;
    chromium = {
     enablePepperFlash = true;
     enablePepperPDF = true;
    };
  };

}
