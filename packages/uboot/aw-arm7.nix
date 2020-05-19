{ pkgs }:

let
  defConfigs = [
    "Sinovoip_BPI_M3_defconfig"
    "nanopi_neo_defconfig"
    "nanopi_neo_air_defconfig"
    "orangepi_zero_defconfig"
  ];
  version = "2020.04";
  src = pkgs.fetchurl {
    url = "ftp://ftp.denx.de/pub/u-boot/u-boot-${version}.tar.bz2";
    sha256 = "0wjkasnz87q86hx93inspdjfjsinmxi87bcvj30c773x0fpjlwzy";
  };
  buildAllwinnerUboot = (defconfig:
    pkgs.pkgsCross.armv7l-hf-multiplatform.buildUBoot {
      inherit src version defconfig;
      extraPatches = [
        (pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/armbian/build/master/patch/u-boot/u-boot-sunxi/h3-Fix-PLL1-setup-to-never-use-dividers.patch";
          sha256 = "11spjq29d7hqxkpni8db72jblxvpa6jc8aw4hkf0aykf97f14bjd";
        })
        (pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/armbian/build/master/patch/u-boot/u-boot-sunxi/add-nanopi-duo.patch";
          sha256 = "19wiri7hxv6r3g3z3a55hywz63d4p7n9kj3hw7yhlgqjhxnprd3d";
        })
        (pkgs.writeText "patch"''
          --- a/arch/arm/dts/sun8i-h3-nanopi-neo-air.dts
          +++ b/arch/arm/dts/sun8i-h3-nanopi-neo-air.dts
          @@ -103,6 +103,23 @@
           	};
           };

          +&mmc2 {
          +	pinctrl-names = "default";
          +	pinctrl-0 = <&mmc2_8bit_pins>;
          +	vmmc-supply = <&reg_vcc3v3>;
          +	bus-width = <8>;
          +	non-removable;
          +	cap-mmc-hw-reset;
          +	status = "okay";
          +};
          +
          +&mmc2_8bit_pins {
          +	/* Increase drive strength for DDR modes */
          +	drive-strength = <40>;
          +	/* eMMC is missing pull-ups */
          +	bias-pull-up;
          +};
          +
           &uart0 {
           	pinctrl-names = "default";
           	pinctrl-0 = <&uart0_pins_a>;
          --- a/configs/nanopi_neo_air_defconfig
          +++ b/configs/nanopi_neo_air_defconfig
          @@ -16,3 +16,4 @@ CONFIG_SPL=y
           # CONFIG_SPL_EFI_PARTITION is not set
           CONFIG_USB_EHCI_HCD=y
           CONFIG_USB_OHCI_HCD=y
          +CONFIG_MMC_SUNXI_SLOT_EXTRA=2
        ''
        )
      ];
      extraMeta.platforms = [ "armv7l-linux" ];
      filesToInstall = [ "u-boot-sunxi-with-spl.bin" ];
    });
in pkgs.lib.genAttrs defConfigs (defconfig: pkgs.writeScript "sd-fuse" ''
  echo "writing to $1"
  dd if=${buildAllwinnerUboot defconfig}/u-boot-sunxi-with-spl.bin conv=notrunc of=$1 bs=1024 seek=8
'')
