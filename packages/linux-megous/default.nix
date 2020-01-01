{ stdenv, fetchurl, fetchFromGitHub, perl, linuxManualConfig, flex, bison, dtc, python2, linux_latest, buildPackages, callPackage, ... } @ args:

import <nixpkgs/pkgs/os-specific/linux/kernel/generic.nix> (args // rec {
  version = "5.4";
  modDirVersion = "5.4.0-rc2";

  src = fetchFromGitHub {
    owner = "megous";
    repo = "linux";
    rev = "orange-pi-${version}";
    sha256 = "1qkx7b4mzy9s9gz2hc14167xcr1crq90793ij2iwj5zz7lrhi3jq";
  };

  nativeBuildInputs = [ flex bison dtc python2 ];

  inherit flex bison dtc callPackage;

  /* defconfig = "orangepi_defconfig"; */
  kernelPatches = linux_latest.kernelPatches ++ [
    {
      name = "h265 decoding";
      patch = fetchurl {
        url = "https://patchwork.kernel.org/series/179773/mbox/";
        sha256 = "00dki63nq054f81jjs03zm6ry8n80a6mxckvir9phvyp0m456j1i";
      };
    }
    { name = "spi nor error"; patch = null; extraConfig = ''
        MTD_SPI_NOR n
      ''; }
  ];

} // (args.argsOverride or {}))
