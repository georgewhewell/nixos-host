## Waveshare ESP32-S3-Touch-AMOLED-1.64 (ESP32-S3R8, 16MB flash / 8MB octal PSRAM)
#
# 1.64" AMOLED, 280x456, CO5300 controller on a quad-SPI (MIPI DBI) bus.
# FT3168 capacitive touch + QMI8658C 6-axis IMU share the I2C bus at 47/48.
#
# Pins come from the vendor ESP-IDF demo (main/main.c, components/*_bsp) and
# match upstream ESPHome's WAVESHARE-ESP32-S3-TOUCH-AMOLED-1.64 preset, which
# only exists in esphome >= 2026.7 — we spell the CO5300 out explicitly so the
# config also builds on the 2026.6.x in nixpkgs.
#
# Board revisions differ! This module is wired for **V1**, which is what
# espressif/arduino-esp32's `waveshare_esp32_s3_touch_amoled_164` variant
# describes: QSPI_CS 9, TP_RST -1, TP_INT -1, AMOLED_PWR_EN -1.
#   function   V1        V2
#   LCD_CS     GPIO9     GPIO46
#   IMU_INT1   GPIO46    GPIO9
#   IMU_INT2   -         GPIO17
#   TP_INT     -         GPIO18
#   LCD_TE     -         GPIO45
# Everything else (QSPI clk/data, reset, enable, I2C, TF card, battery ADC) is
# common to both. Flip `boardRev` below for a V1 board.
{...}: let
  boardRev = 1;

  lcdCsPin =
    if boardRev >= 2
    then "GPIO46"
    else "GPIO9";
  # V1 has no touch interrupt line broken out; it is polled instead.
  touchIrqPin =
    if boardRev >= 2
    then "GPIO18"
    else null;
in {
  imports = [
    ./esp32-s3.nix
  ];

  esphome.settings = {
    esp32 = {
      board = "esp32-s3-devkitc-1";
      variant = "esp32s3";
      flash_size = "16MB";
      framework.sdkconfig_options = {
        CONFIG_ESPTOOLPY_FLASHSIZE_16MB = "y";
      };
    };

    i2c = [
      {
        id = "bus_a";
        sda = "GPIO47";
        scl = "GPIO48";
        # 300kHz + internal pullups, exactly what the vendor demo configures.
        frequency = "300kHz";
        sda_pullup_enabled = true;
        scl_pullup_enabled = true;
        # QMI8658C IMU also lives here at 0x6B (no stock ESPHome component).
        scan = true;
      }
    ];

    spi = [
      {
        id = "qspi_bus";
        type = "quad";
        interface = "spi2";
        clk_pin = "GPIO10";
        data_pins = [
          "GPIO11"
          "GPIO12"
          "GPIO13"
          "GPIO14"
        ];
      }
    ];

    display = [
      {
        platform = "mipi_spi";
        model = "CO5300";
        id = "s3_display";
        spi_id = "qspi_bus";
        bus_mode = "quad";
        # The CO5300 die is wider than the glass: the visible window starts at
        # column 20 (the vendor demo adds 0x14 to every x coordinate).
        dimensions = {
          width = 280;
          height = 456;
          offset_width = 20;
          offset_height = 0;
        };
        cs_pin = {
          number = lcdCsPin;
          # V2 wires CS to GPIO46, which is a strapping pin. Nothing we can do
          # about it in software, so don't warn on every build.
          ignore_strapping_warning = boardRev >= 2;
        };
        reset_pin = "GPIO21";
        # NO enable_pin. Upstream ESPHome's 1.64 preset drives GPIO1, but the
        # vendor demo and arduino-esp32's variant header both say this board has
        # no AMOLED_PWR_EN, and driving GPIO1 high leaves the FT3168 silent on
        # I2C while the panel works fine — consistent with GPIO1 being an
        # active-high touch reset. Left floating, as the vendor firmware does.
        data_rate = "40MHz";
        color_order = "rgb";
        # Vendor demo rounds every flush area to even coordinates.
        draw_rounding = 2;
        brightness = 208; # 0xD0, same default as upstream
        auto_clear_enabled = false;
        update_interval = "never";
        show_test_card = false;
      }
    ];

    touchscreen = [
      ({
          platform = "ft5x06"; # FT3168 speaks the FocalTech register set
          id = "s3_touch";
          i2c_id = "bus_a";
          # ESPHome's ft5x06 defaults to 0x48; the FT3168 sits at 0x38.
          address = "0x38";
          display = "s3_display";
          # Vendor demo maps raw X->x, raw Y->y, so no transform is needed.
          #
          # Per the board schematic, the display FPC brings out TP_SCL (pin 3,
          # IO48) and TP_SDA (pin 5, IO47) with 10K pullups, TP_VCC (pin 11)
          # hard-tied to 3V3, and leaves TP_INT (pin 7) and TP_RESET (pin 9)
          # as no-connects. So: polled only, no reset, no power sequencing —
          # there is nothing here for firmware to get wrong. If the boot I2C
          # scan shows 0x6B (IMU) but no 0x38, the touch controller itself is
          # not answering and the fault is in the panel/FPC, not this config.
        }
        // (
          if touchIrqPin != null
          then {interrupt_pin = touchIrqPin;}
          else {}
        ))
    ];

    # AMOLED has no backlight; "brightness" is a panel register write.
    output = [
      {
        platform = "template";
        id = "display_brightness";
        type = "float";
        write_action."then" = [
          {lambda = "id(s3_display).set_brightness(state * 255);";}
        ];
      }
    ];

    light = [
      {
        platform = "monochromatic";
        id = "display_backlight";
        name = "Display Brightness";
        output = "display_brightness";
        default_transition_length = "0ms";
        restore_mode = "RESTORE_DEFAULT_ON";
        initial_state.brightness = "80%";
      }
    ];

    sensor = [
      {
        # Battery header sits behind a 1:3 divider into ADC1_CH3 (GPIO4).
        platform = "adc";
        pin = "GPIO4";
        id = "battery_voltage";
        name = "Battery Voltage";
        device_class = "voltage";
        unit_of_measurement = "V";
        accuracy_decimals = 2;
        attenuation = "12db";
        update_interval = "60s";
        filters = [
          {multiply = 3.0;}
          {
            sliding_window_moving_average = {
              window_size = 5;
              send_every = 5;
            };
          }
        ];
      }
    ];

    binary_sensor = [
      {
        platform = "gpio";
        pin = {
          number = "GPIO0";
          inverted = true;
          mode.input = true;
        };
        id = "boot_button";
        name = "Boot Button";
      }
    ];

    # TF card (SDMMC 1-bit): CLK GPIO41, CMD GPIO39, D0 GPIO40 — unused here.
  };
}
