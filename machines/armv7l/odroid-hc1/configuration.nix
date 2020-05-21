{ config, pkgs, lib, ... }:

{
  networking.hostName = "odroid-hc1";
  nix.buildCores = 7;

  boot.kernelPatches = [
    {
      name = "fix dts name";
      patch = pkgs.writeText "patch" ''
        diff --git a/arch/arm/boot/dts/Makefile b/arch/arm/boot/dts/Makefile
        index e8dd99201397..142e5a28783c 100644
        --- a/arch/arm/boot/dts/Makefile
        +++ b/arch/arm/boot/dts/Makefile
        @@ -208,7 +208,7 @@ dtb-$(CONFIG_ARCH_EXYNOS5) += \
         	exynos5420-arndale-octa.dtb \
         	exynos5420-peach-pit.dtb \
         	exynos5420-smdk5420.dtb \
        -	exynos5422-odroidhc1.dtb \
        +	exynos5422-odroid.dtb \
         	exynos5422-odroidxu3.dtb \
         	exynos5422-odroidxu3-lite.dtb \
         	exynos5422-odroidxu4.dtb \
        diff --git a/arch/arm/boot/dts/exynos5422-odroidhc1.dts b/arch/arm/boot/dts/exynos5422-odroid.dts
        similarity index 100%
        rename from arch/arm/boot/dts/exynos5422-odroidhc1.dts
        rename to arch/arm/boot/dts/exynos5422-odroid.dts
      '';
    }
  ];

  imports = [
    ../common.nix
  ];

}
