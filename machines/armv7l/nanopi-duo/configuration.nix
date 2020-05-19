{ config, pkgs, lib, ... }:

{

  networking.hostName = "nanopi-duo";

  hardware.firmware = with pkgs; [ armbian-firmware ];

  boot.initrd.availableKernelModules = [ "sunxi" "wire" ];

  boot.kernelParams = [ "boot.shell_on_fail" "console=ttyS0,115200" "console=ttyACM0,115200"  "earlycon=uart,mmio32,0x1c28000" ];
  console.extraTTYs = [ "ttyS0" ];

  environment.systemPackages = with pkgs; [
    i2c-tools
  ];

  imports = [
    ../common.nix
  ];

  usb-gadget = {
    enable = true;
    initrdDHCP = true;
  };

  hardware.deviceTree = {
    enable = true;
    base = pkgs.runCommandNoCC "mydtb" {} ''
      mkdir $out
      cp ${config.boot.kernelPackages.kernel}/dtbs/${config.hardware.devicetree.dtbName}.dtb $out/
    '';
    overlays = [
      "${pkgs.dt-overlays}/nanopi-air-bt.dts.dtbo"
      "${pkgs.dt-overlays}/sunxi-power-button.dts.dtbo"
    ];
  };

  hardware.devicetree = {
    enable = true;
    dtbName = "sun8i-h2-plus-nanopi-duo";
    overlays = let
      sunxi-i2c0-solomon = ''
        /dts-v1/;
        /plugin/;

        / {
            compatible = "allwinner,sun8i-h3";

            fragment@0 {
        	     target = <&i2c0>;
            	__overlay__ {
            	    status = "okay";

            	    #address-cells = <1>;
            	    #size-cells = <0>;

            	    ssd1306: oled@3c{
                		compatible = "solomon,ssd1306fb-i2c";
                		reg = <0x3c>;
                		solomon,width = <128>;
                		solomon,height = <32>;
                		solomon,page-offset = <0>;
                    solomon,baud-rate = <1000000>;
            	    };
        	     };
            };

          __overrides__ {
          	address = <&ssd1306>,"reg:0";
          	width = <&ssd1306>,"solomon,width:0";
          	height = <&ssd1306>,"solomon,height:0";
          	offset = <&ssd1306>,"solomon,page-offset:0";
          	normal = <&ssd1306>,"solomon,segment-no-remap?";
          	sequential = <&ssd1306>,"solomon,com-seq?";
          	remapped = <&ssd1306>,"solomon,com-lrremap?";
          	inverted = <&ssd1306>,"solomon,com-invdir?";
          };
        };
      '';
      sunxi-i2c0-enable = ''
        /dts-v1/;
        /plugin/;

        / {
        	compatible = "allwinner,sun8i-h3";

        	fragment@0 {
        		target-path = "/aliases";
        		__overlay__ {
        			i2c0 = "/soc/i2c@01c2ac00";
        		};
        	};

        	fragment@1 {
        		target = <&i2c0>;
        		__overlay__ {
        			status = "okay";
        		};
        	};
        };
        '';
      sunxi-add-spi1 = ''
        /dts-v1/;
        /plugin/;

        / {
        	compatible = "allwinner,sun8i-h3";

        	fragment@0 {
        		target = <&pio>;
        		__overlay__ {
        			spi0_cs1: spi0_cs1 {
        				pins = "PA21";
        				function = "gpio_out";
        				output-high;
        			};

        			spi1_cs1: spi1_cs1 {
        				pins = "PA10";
        				function = "gpio_out";
        				output-high;
        			};
        		};
        	};

        	fragment@1 {
        		target = <&spi0>;
        		__overlay__ {
        			pinctrl-names = "default", "default";
        			pinctrl-1 = <&spi0_cs1>;
        			cs-gpios = <0>, <&pio 0 21 0>; /* PA21 */
        		};
        	};

        	fragment@2 {
        		target = <&spi1>;
        		__overlay__ {
        			pinctrl-names = "default", "default";
        			pinctrl-1 = <&spi1_cs1>;
        			cs-gpios = <0>, <&pio 0 10 0>; /* PA10 */
        		};
        	};
        };
      '';
      sunxi-spidev = ''
        /dts-v1/;
        /plugin/;

        / {
        compatible = "allwinner,sun8i-h3";

        fragment@0 {
          target-path = "/aliases";
          __overlay__ {
            spi0 = "/soc/spi@01c68000";
            spi1 = "/soc/spi@01c69000";
          };
        };

        fragment@1 {
          target = <&spi0>;
          __overlay__ {
            #address-cells = <1>;
            #size-cells = <0>;
            spidev {
              compatible = "spidev";
              status = "okay";
              reg = <0>;
              spi-max-frequency = <1000000>;
            };
          };
        };

        fragment@2 {
          target = <&spi1>;
          __overlay__ {
            #address-cells = <1>;
            #size-cells = <0>;
            spidev {
              compatible = "spidev";
              status = "okay";
              reg = <0>;
              spi-max-frequency = <1000000>;
            };
          };
        };
      };
      '';
      sunxi-i2c0-pcapwm = ''
        /dts-v1/;
        /plugin/;

        / {
          compatible = "allwinner,sun8i-h3";

        	fragment@0 {
        		target = <&i2c0>;

            __overlay__ {
                status = "okay";

          	    #address-cells = <1>;
          	    #size-cells = <0>;

                pca9685-0@40 {
                    compatible = "nxp,pca9685-pwm";
                    reg = <0x40>;
                    status = "okay";
                };
            };
        	};
        };
      '';
    in [ ];
  };

  system.build.ubootDefconfig = "nanopi_duo_defconfig";

}
