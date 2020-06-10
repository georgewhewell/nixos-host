{ stdenv, sources, dtc, linux, writeText }:
let
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
            dc-gpios = <&gpio >;
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
  sunxi-nanopi-air-bt = ''
    /dts-v1/;
    /plugin/;

    / {
      compatible = "allwinner,sun8i-h3";

      fragment@0 {
        target = <&uart3>;

        __overlay__ {
            pinctrl-names = "default";
            pinctrl-0 = <&uart3_pins>;

            bluetooth@1 {
                reg = <1>;
                compatible = "brcm,bcm43438-bt";
                max-speed = <1500000>;
            };
        };
      };
    };
  '';
  custom = [
    ssd1130Overlay
    sunxi-nanopi-air-bt
  ];
in
stdenv.mkDerivation {
  pname = "sunxi-dt-overlays";

  version = sources.sunxi-DT-overlays.rev;
  src = sources.sunxi-DT-overlays;

  nativeBuildInputs = [ dtc ];

  buildPhase = ''
    for dts in $(find . -iname '*.dts'); do
      echo -n "Converting $dts";
      dtc -@ $dts -O dtb -o $dts.dtbo && echo ' [Done]';
    done
  '';

  installPhase = ''
    mkdir -p $out
    cp -rv * $out
  '';

}
