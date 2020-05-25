{ config, lib, pkgs, ... }:

{
  imports = [
    ../common-arm.nix
  ];

  nixpkgs.overlays = [
    (self: super: {
        bluez = (let
          python3_ = super.python3.override {
            packageOverrides = python-self: python-super: {
              pygobject3 = python-super.pygobject3.overrideAttrs (oldAttrs: {
                propagatedBuildInputs = [];
                PYGOBJECT_WITHOUT_PYCAIRO = 1;
                mesonFlags = oldAttrs.mesonFlags ++ [
                  "-Dpycairo=false"
                ];
              });
            };
          };
        in
          (super.bluez.override({
            python3 = python3_;
            libical = super.libical.overrideAttrs(o: {
              doInstallCheck = false;
            });
          })).overrideAttrs(o: {
            patches = [
              (super.fetchurl {
                url = "https://raw.githubusercontent.com/OpenELEC/OpenELEC.tv/6b9e7aaba7b3f1e7b69c8deb1558ef652dd5b82d/packages/network/bluez/patches/bluez-07-broadcom-dont-set-speed-before-loading.patch";
                sha256 = "1qgihk1vbwn5msk9rj7xwybcn0kwd0pzq7sh2vljgkng5ixxxff3";
              })
            ];
          })
        );
    })
  ];

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_megous;

  # takes ages
  security.polkit.enable = lib.mkForce false;
  services.udisks2.enable = lib.mkForce false;

  services.mingetty.autologinUser = lib.mkForce "grw";
  # sd card image must be <2gb
#  environment.systemPackages = with pkgs; lib.mkForce [ bash nix coreutils systemd ];

  boot.kernelPatches = [
    {
      name = "gpio-sysfs";
      patch = null;
      extraConfig = ''
        GPIO_SYSFS y
      '';
    }
    {
      name = "nanopi-air";
      patch = ./nanopi-air-nand-wifi.patch;
    }
    {
      name = "rfkill";
      patch = pkgs.writeText "sunxi-rfkill" ''
      diff --git a/net/rfkill/rfkill-gpio.c b/net/rfkill/rfkill-gpio.c
      index 76c01cbd56e35..656847bdf00d5 100644
      --- a/net/rfkill/rfkill-gpio.c
      +++ b/net/rfkill/rfkill-gpio.c
      @@ -35,7 +35,7 @@ struct rfkill_gpio_data {

       	struct rfkill		*rfkill_dev;
       	struct clk		*clk;
      -
      +	int             clk_frequency;
       	bool			clk_enabled;
       };

      @@ -44,13 +44,13 @@ static int rfkill_gpio_set_power(void *data, bool blocked)
       	struct rfkill_gpio_data *rfkill = data;

       	if (!blocked && !IS_ERR(rfkill->clk) && !rfkill->clk_enabled)
      -		clk_enable(rfkill->clk);
      +		clk_prepare_enable(rfkill->clk);

       	gpiod_set_value_cansleep(rfkill->shutdown_gpio, !blocked);
       	gpiod_set_value_cansleep(rfkill->reset_gpio, !blocked);

       	if (blocked && !IS_ERR(rfkill->clk) && rfkill->clk_enabled)
      -		clk_disable(rfkill->clk);
      +		clk_disable_unprepare(rfkill->clk);

       	rfkill->clk_enabled = !blocked;

      @@ -96,8 +96,9 @@ static int rfkill_gpio_probe(struct platform_device *pdev)
       	if (!rfkill)
       		return -ENOMEM;

      -	device_property_read_string(&pdev->dev, "name", &rfkill->name);
      -	device_property_read_string(&pdev->dev, "type", &type_name);
      +	device_property_read_string(&pdev->dev, "rfkill-name", &rfkill->name);
      +	device_property_read_string(&pdev->dev, "rfkill-type", &type_name);
      +	device_property_read_u32(&pdev->dev, "clock-frequency", &rfkill->clk_frequency);

       	if (!rfkill->name)
       		rfkill->name = dev_name(&pdev->dev);
      @@ -111,6 +112,9 @@ static int rfkill_gpio_probe(struct platform_device *pdev)
       	}

       	rfkill->clk = devm_clk_get(&pdev->dev, NULL);
      +	if (!IS_ERR(rfkill->clk) && rfkill->clk_frequency > 0) {
      +		clk_set_rate(rfkill->clk, rfkill->clk_frequency);
      +	}

       	gpio = devm_gpiod_get_optional(&pdev->dev, "reset", GPIOD_OUT_LOW);
       	if (IS_ERR(gpio))
      @@ -167,6 +171,10 @@ static const struct acpi_device_id rfkill_acpi_match[] = {
       };
       MODULE_DEVICE_TABLE(acpi, rfkill_acpi_match);
       #endif
      +static const struct of_device_id rfkill_of_match[] = {
      +	{ .compatible = "rfkill-gpio", },
      +	{},
      +};

       static struct platform_driver rfkill_gpio_driver = {
       	.probe = rfkill_gpio_probe,
      @@ -174,6 +182,7 @@ static struct platform_driver rfkill_gpio_driver = {
       	.driver = {
       		.name = "rfkill_gpio",
       		.acpi_match_table = ACPI_PTR(rfkill_acpi_match),
      +		.of_match_table = of_match_ptr(rfkill_of_match),
       	},
       };

      '';
    }
    {
      name = "nanopi-duo";
      patch = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/armbian/build/master/patch/kernel/sunxi-dev/board-h2plus-nanopi-duo-add-device.patch";
        sha256 = "1vksyr3icjf0j53fmsghbj5bl1ip25v4kh0s7lm3s91mdk5kk86m";
      };
      extraConfig = ''
        USB_DWC2 m
        USB_OTG y
        USB_WDM m
        U_SERIAL_CONSOLE y
        USB_SNP_CORE m
        USB_SNP_UDC_PLAT m
        USB_F_ACM m
        USB_F_SS_LB m
        USB_U_SERIAL m
        USB_U_AUDIO m
        USB_F_SERIAL m
        USB_F_OBEX m
        USB_F_NCM m
        USB_F_EEM m
        USB_F_MASS_STORAGE m
        USB_F_FS m
        USB_F_UAC1 m
        USB_F_UAC2 m
        USB_F_UVC m
        USB_F_MIDI m
        USB_F_HID m
        USB_F_PRINTER m
        USB_MUSB_GADGET m
        USB_GADGET y
        USB_CONFIGFS m
        USB_CONFIGFS_SERIAL y
        USB_CONFIGFS_ACM y
        USB_CONFIGFS_OBEX y
        USB_CONFIGFS_NCM y
        USB_CONFIGFS_ECM y
        USB_CONFIGFS_ECM_SUBSET y
        USB_CONFIGFS_RNDIS y
        USB_CONFIGFS_EEM y
        USB_CONFIGFS_MASS_STORAGE y
        USB_CONFIGFS_F_LB_SS y
        USB_CONFIGFS_F_FS y
        USB_CONFIGFS_F_UAC1 y
        USB_CONFIGFS_F_UAC1_LEGACY y
        USB_CONFIGFS_F_UAC2 y
        USB_CONFIGFS_F_MIDI y
        USB_CONFIGFS_F_HID y
        USB_CONFIGFS_F_UVC y
        USB_ETH_EEM y
        USB_G_NCM m
        USB_GADGETFS m
        USB_FUNCTIONFS m
        USB_FUNCTIONFS_ETH y
        USB_FUNCTIONFS_RNDIS y
        USB_MASS_STORAGE m
        USB_G_SERIAL m
        USB_MIDI_GADGET m
        USB_G_PRINTER m
        USB_CDC_COMPOSITE m
        USB_G_ACM_MS m
        USB_G_MULTI m
        USB_G_MULTI_RNDIS y
        USB_G_MULTI_CDC y
      '';
    }
  ];

}
