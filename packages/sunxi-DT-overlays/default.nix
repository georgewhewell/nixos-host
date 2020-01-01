{ stdenv, fetchgit, dtc, linux, writeText }:

let
  pinnedVersion = stdenv.lib.importJSON ./src.json;
  spi-enabled = writeText "spi-enable.dts" ''
    /dts-v1/;
    /plugin/;

    / {
      compatible = "allwinner,sun8i-h5";
    	fragment@0 {
    		target = <&spi0>;
    		__overlay__ {
    			#address-cells = <1>;
    			#size-cells = <0>;
    			status = "okay";
    		};
    	};

    	fragment@1 {
    		target = <&spi1>;
    		__overlay__ {
    			#address-cells = <1>;
    			#size-cells = <0>;
    			status = "okay";
    		};
    	};
    };

  '';
  ssd1130Overlay = writeText "oled-spi.dts" ''
    /dts-v1/;
    /plugin/;

    / {
      compatible = "amlogic,meson-gxbb";
      fragment@0 {
        target = <&gpio>;
        __overlay__ {
          oled_pins: oled_pins {
            pins = "PA2", "PC7";
            function = "gpio_out";
          };
        };
      };

      fragment@1 {
        target = <&spi1>;
        __overlay__ {
          /* needed to avoid dtc warning */
          #address-cells = <1>;
          #size-cells = <0>;
          status = "okay";
          oled_display: oled_display@0{
            compatible = "solomon,ssd1351";
            reg = <0>;
            pinctrl-names = "default";
            pinctrl-0 = <&oled_pins>;
            spi-max-frequency = <10000000>;
            buswidth = <8>;
            dc-gpios = <&pio 2 7 0>;
            #debug = <4>;
            rotate = <0>;
          };
        };
      };

      __overrides__ {
        #speed =      <&oled_display>,"spi-max-frequency:0";
        #rotate =     <&oled_display>,"rotate:0";
        fps =         <&oled_display>,"fps:0";
        #debug =      <&oled_display>,"debug:0";
      };
    };
  '';
in stdenv.mkDerivation {
  name = "sunxi-dt-overlays-${pinnedVersion.rev}";
  src = fetchgit {
    inherit (pinnedVersion) url rev sha256;
  };

  nativeBuildInputs = [ dtc ];
  # Rename DTBs so u-boot finds them, like linux-rpi.nix

  buildPhase = ''
    for dts in $(find . -iname '*.dts'); do
      echo -n "Converting $dts";
      dtc -@ $dts -O dtb -o $dts.dtbo && echo ' [Done]';
    done
    # dtc -@ ${spi-enabled} -O dtb -o spi-enabled.dtbo
    dtc -@ ${ssd1130Overlay} -O dtb -o ssd1351-spi.dtbo
  '';

  installPhase = ''
    mkdir -p $out
    cp -rv * $out
  '';

}
