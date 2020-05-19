{ config, pkgs, lib, ... }:

{

  networking.hostName = "odroid-c1";

  imports = [
    ../common.nix
  ];

  boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor (pkgs.linux_testing.override {
    argsOverride = rec {
      src = pkgs.fetchFromGitHub {
        owner = "xdarklight";
        repo = "linux";
        rev = "meson-mx-integration-5.8-20200520";
        sha256 = "0iyhvq5l536a501m0xmj3s84xz50p0q4z3kyj4i57f43g0bflxa0";
      };
      version = "5.7-rc6";
      modDirVersion = "5.7.0-rc6";
    };
  }));

}
