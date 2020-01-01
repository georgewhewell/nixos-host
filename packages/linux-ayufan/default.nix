{ stdenv, fetchFromGitHub, perl, linuxManualConfig, flex, bison, dtc, python2, linux_testing, buildPackages, callPackage, ... } @ args:

let
  pinnedVersion = stdenv.lib.importJSON ./src.json;
in
  import <nixpkgs/pkgs/os-specific/linux/kernel/generic.nix> (args // rec {
    version = "5.4";
    modDirVersion = "5.4.0-rc1";

    src = fetchFromGitHub {
      owner = "ayufan-rock64";
      repo = "linux-mainline-kernel";
      rev = "master";
      sha256 = "0nd34080qyvmvfd7cnx7lb3v85lzs6n6d68ipknkdzcxxh2s5039";
    };

    nativeBuildInputs = [ flex bison dtc python2 ];

    inherit  flex bison dtc buildPackages callPackage;

    defconfig = "rockchip_linux_defconfig";

} // (args.argsOverride or {}))
