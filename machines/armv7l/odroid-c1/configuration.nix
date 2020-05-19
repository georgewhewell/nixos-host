{ config, pkgs, lib, ... }:

{

  networking.hostName = "odroid-c1";

  imports = [
    ../common.nix
  ];

  boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.linux_testing.override {
    argsOverride = rec {
      src = pkgs.fetchFromGitHub {
        owner = "xdarklight";
        repo = "linux";
        rev = "meson-mx-integration-5.8-20200520";
        sha256 = "17lwdaw601casry2pknj52hnmyqbcfyw5ai09y8yn0shh72221x7";
      };
      version = "5.7-rc6";
      modDirVersion = "5.7.0-rc6";
    };
  });

}
