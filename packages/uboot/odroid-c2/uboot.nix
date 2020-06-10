{ lib, buildUBoot, fetchFromGitHub }:

buildUBoot {
  defconfig = "odroid-c2_defconfig";
  extraMeta.platforms = [ "aarch64-linux" ];
  filesToInstall = [ "u-boot.bin" ];
}
