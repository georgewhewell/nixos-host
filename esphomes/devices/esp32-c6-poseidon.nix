{...}: let
  ntcCalibration = [
    "194.3kOhm -> -40°C"
    "10kOhm -> 25°C"
    "0.530kOhm -> 125°C"
  ];

  mkNtcPairSensors = {
    index,
    rawSensorId,
  }: let
    idx = toString index;
    baseId = "ntc${idx}";
    adcId = "${baseId}_adc";
    resistanceId = "${baseId}_resistance";
    temperatureId = "${baseId}_temp";
    label = "NTC ${idx}";
  in [
    {
      platform = "template";
      name = "${label} ADC Voltage";
      id = adcId;
      unit_of_measurement = "V";
      device_class = "voltage";
      state_class = "measurement";
      accuracy_decimals = 3;
      update_interval = "5s";
      entity_category = "diagnostic";
      lambda = ''
        if (isnan(id(${rawSensorId}).state)) {
          return NAN;
        }
        const float raw = id(${rawSensorId}).state;
        if (raw <= -450.0f || raw >= 500.0f) {
          return NAN;
        }
        return 1.2f - (raw * 0.00078125f);
      '';
    }
    {
      platform = "template";
      name = "${label} Resistance";
      id = resistanceId;
      unit_of_measurement = "Ω";
      icon = "mdi:flash";
      state_class = "measurement";
      accuracy_decimals = 1;
      update_interval = "5s";
      entity_category = "diagnostic";
      lambda = ''
        if (isnan(id(${adcId}).state)) {
          return NAN;
        }
        const float v = id(${adcId}).state;
        const float denom = 3.3f - (2.0f * v);
        if (v <= 0.0f || denom <= 0.01f) {
          return NAN;
        }
        return 3300.0f * v / denom;
      '';
    }
    {
      platform = "ntc";
      sensor = resistanceId;
      id = temperatureId;
      name = "${label} Temperature";
      calibration = ntcCalibration;
    }
  ];

  mkIna3221Channel = channel: {
    shunt_resistance = "0.1 ohm";
    current = {
      name = "INA3221 Channel ${toString channel} Current";
      filters = [{delta = 0.01;}];
    };
    power = {
      name = "INA3221 Channel ${toString channel} Power";
      filters = [{delta = 0.1;}];
    };
    bus_voltage = {
      name = "INA3221 Channel ${toString channel} Bus Voltage";
      filters = [{delta = 0.05;}];
    };
    shunt_voltage = {
      name = "INA3221 Channel ${toString channel} Shunt Voltage";
      filters = [{delta = 0.1;}];
    };
  };

  ina3221Channels = builtins.listToAttrs (builtins.map (channel: {
    name = "channel_${toString channel}";
    value = mkIna3221Channel channel;
  }) [1 2 3]);

  mkPulseCounter = {
    id,
    name,
    pin,
    unit,
    filters,
    updateInterval ? "5s",
  }: {
    platform = "pulse_counter";
    pin = {
      number = pin;
      mode = "INPUT_PULLUP";
    };
    unit_of_measurement = unit;
    inherit id name filters;
    update_interval = updateInterval;
  };

  mkRpmPulseCounter = {
    id,
    name,
    pin,
  }:
    mkPulseCounter {
      inherit id name pin;
      unit = "RPM";
      filters = [{multiply = 0.5;}];
    };
in {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
  ];

  esphome.settings = {
    substitutions.name = "esp32-c6-poseidon";

    esphome = {
      name = "\${name}";
      friendly_name = "\${name}";
      on_boot = {
        priority = -100;
        "then" = [
          {
            "select.set" = {
              id = "pd_voltage";
              option = "20V";
            };
          }
          # Ensure pumps run after boot, but keep the restored speed rather
          # than stomping Manual/Max settings with a fixed value.
          {"fan.turn_on" = "mora_pumps";}
        ];
      };
    };

    esp32 = {
      board = "esp32-c6-devkitm-1";
      framework = {
        type = "esp-idf";
        version = "latest";
        sdkconfig_options = {
          CONFIG_HTTPD_MAX_REQ_HDR_LEN = "1024";
          CONFIG_HTTPD_MAX_URI_LEN = "512";
          CONFIG_HTTPD_MAX_RESP_HDR_LEN = "1024";
          CONFIG_ESP_MAIN_TASK_STACK_SIZE = "8192";
          CONFIG_FREERTOS_TIMER_TASK_STACK_DEPTH = "3072";
          CONFIG_ESP_JTAG_USB_ENABLE = "n";
          CONFIG_ESP_JTAG_ENABLED = "n";
        };
      };
    };

    external_components = [
      {
        source = "github://pr#6693";
        refresh = "10s";
        components = ["husb238"];
      }
      # `lis3dh` here is a vendored copy of the component from a local
      # ESPHome `feat/lis3dh` branch (had ADC1/ADC2 + temperature support
      # the upstream component lacks). Source files live under
      # esphomes/external-components/lis3dh/ and are made available to
      # the dashboard via the prestart symlink at
      # /var/lib/esphome/external-components.
      {
        source = {
          type = "local";
          path = "external-components";
        };
        components = ["lis3dh"];
      }
    ];

    i2c = [
      {
        id = "i2c_screen";
        sda = "GPIO1";
        scl = "GPIO0";
        scan = true;
        frequency = "800kHz";
      }
      {
        id = "i2c_bus";
        sda = "GPIO6";
        scl = "GPIO7";
        scan = true;
        low_power_mode = true;
        frequency = "100kHz";
      }
    ];

    font = [
      {
        file = "gfonts://Roboto Mono";
        id = "oled_font";
        size = 8;
      }
    ];

    display = [
      {
        platform = "ssd1306_i2c";
        i2c_id = "i2c_screen";
        model = "SSD1306 72x40";
        rotation = 0;
        update_interval = "2s";
        offset_y = 0;
        offset_x = 0;
        invert = false;
        address = "0x3C";
        show_test_card = false;
        lambda = ''
          auto line_i = [&](int y, const char *label, float value) {
            if (isnan(value)) {
              it.printf(0, y, id(oled_font), "%s --", label);
            } else {
              it.printf(0, y, id(oled_font), "%s %4.0f", label, value);
            }
          };
          auto line_f = [&](int y, const char *label, float value) {
            if (isnan(value)) {
              it.printf(0, y, id(oled_font), "%s --.-", label);
            } else {
              it.printf(0, y, id(oled_font), "%s %4.1f", label, value);
            }
          };
          const uint8_t page = (millis() / 5000UL) % 3U;
          if (page == 0) {
            line_i(0,  "P1", id(mora_pump1_rpm).has_state() ? id(mora_pump1_rpm).state : NAN);
            line_i(10, "P2", id(mora_pump2_rpm).has_state() ? id(mora_pump2_rpm).state : NAN);
            line_i(20, "FN", id(mora_fan1_rpm).has_state() ? id(mora_fan1_rpm).state : NAN);
            line_i(30, "FL", id(mora_flow_rate).has_state() ? id(mora_flow_rate).state : NAN);
          } else if (page == 1) {
            line_f(0,  "T1", id(ntc1_temp).has_state() ? id(ntc1_temp).state : NAN);
            line_f(10, "T2", id(ntc2_temp).has_state() ? id(ntc2_temp).state : NAN);
            line_f(20, "LIS", id(lis3dh_temp).has_state() ? id(lis3dh_temp).state : NAN);
            line_f(30, "MCU", id(system_internal_temperature).has_state() ? id(system_internal_temperature).state : NAN);
          } else {
            line_i(0,  "A1", id(lis3dh_adc1_raw).has_state() ? id(lis3dh_adc1_raw).state : NAN);
            line_i(10, "A2", id(lis3dh_adc2_raw).has_state() ? id(lis3dh_adc2_raw).state : NAN);
            line_f(20, "MCU", id(system_internal_temperature).has_state() ? id(system_internal_temperature).state : NAN);
            if (!id(system_uptime).has_state()) {
              it.printf(0, 30, id(oled_font), "UP --");
            } else {
              const uint32_t s = (uint32_t) id(system_uptime).state;
              const uint32_t h = s / 3600U;
              const uint32_t m = (s % 3600U) / 60U;
              if (h < 100U) {
                it.printf(0, 30, id(oled_font), "UP %02u:%02u", (unsigned) h, (unsigned) m);
              } else {
                it.printf(0, 30, id(oled_font), "UP %3uh", (unsigned) h);
              }
            }
          }
        '';
      }
    ];

    husb238 = {
      id = "husb_01";
      i2c_id = "i2c_bus";
    };

    binary_sensor = [
      {
        platform = "husb238";
        attached = "PD Attached";
      }
      {
        platform = "homeassistant";
        id = "ha_max_perf_all";
        entity_id = "input_boolean.max_perf_all";
        internal = true;
      }
    ];

    text_sensor = [
      {
        platform = "husb238";
        status = "PD Last Request Status";
        capabilities = "PD Capabilities";
      }
    ];

    select = [
      {
        platform = "husb238";
        voltage = {
          id = "pd_voltage";
          name = "PD Voltage";
        };
      }
      {
        platform = "template";
        id = "cooling_mode";
        name = "Cooling Mode";
        optimistic = true;
        restore_value = true;
        initial_option = "Auto";
        options = ["Manual" "Auto" "Max"];
        set_action = [
          {
            lambda = ''
              if (x == "Max") {
                auto fan_call = id(mora_fan1).turn_on();
                fan_call.set_speed(100);
                fan_call.perform();
                auto pump_call = id(mora_pumps).turn_on();
                pump_call.set_speed(100);
                pump_call.perform();
              } else if (x == "Auto") {
                auto pump_call = id(mora_pumps).turn_on();
                pump_call.set_speed(75);
                pump_call.perform();
              }
            '';
          }
        ];
      }
    ];

    globals = [
      {
        id = "mora_auto_fan_speed_pct";
        type = "int";
        restore_value = "no";
        initial_value = "35";
      }
    ];

    sensor =
      [
        # LIS3DH accelerometer + ADC
        {
          platform = "lis3dh";
          i2c_id = "i2c_bus";
          address = "0x19";
          update_interval = "5s";
          acceleration_x = {
            name = "LIS3DH Acceleration X";
            id = "lis3dh_accel_x";
          };
          acceleration_y = {
            name = "LIS3DH Acceleration Y";
            id = "lis3dh_accel_y";
          };
          acceleration_z = {
            name = "LIS3DH Acceleration Z";
            id = "lis3dh_accel_z";
          };
          adc1 = {
            name = "LIS3DH ADC1 Raw";
            id = "lis3dh_adc1_raw";
          };
          adc2 = {
            name = "LIS3DH ADC2 Raw";
            id = "lis3dh_adc2_raw";
          };
          temperature = {
            name = "LIS3DH Temperature";
            id = "lis3dh_temp";
          };
        }
      ]
      ++ (mkNtcPairSensors {
        index = 1;
        rawSensorId = "lis3dh_adc2_raw";
      })
      ++ (mkNtcPairSensors {
        index = 2;
        rawSensorId = "lis3dh_adc1_raw";
      })
      ++ [
        # HUSB238 USB-PD
        {
          platform = "husb238";
          voltage = "PD Contracted Voltage";
          current = "PD Contracted Current";
          selected_voltage = "PD Selected Voltage";
        }

        # INA3221 3-channel power monitor
        ({
          platform = "ina3221";
          i2c_id = "i2c_bus";
          address = "0x40";
          update_interval = "5s";
        }
        // ina3221Channels)

        # Pulse counters
        (mkRpmPulseCounter {
          id = "mora_pump1_rpm";
          name = "MoRa Pump 1 RPM";
          pin = 2;
        })
        (mkRpmPulseCounter {
          id = "mora_pump2_rpm";
          name = "MoRa Pump 2 RPM";
          pin = 5;
        })
        (mkRpmPulseCounter {
          id = "mora_fan1_rpm";
          name = "MoRa Fans RPM";
          pin = 19;
        })
        (mkPulseCounter {
          id = "mora_flow_rate";
          name = "MoRa Flow Rate";
          pin = 18;
          unit = "L/h";
          filters = [
            {
              calibrate_linear = [
                "327 -> 40"
                "369 -> 50"
                "404 -> 60"
                "449 -> 70"
                "493 -> 80"
                "510 -> 90"
                "560 -> 100"
                "640 -> 110"
                "700 -> 120"
                "737 -> 130"
                "783 -> 140"
                "850 -> 150"
                "960 -> 160"
                "1034 -> 170"
                "1064 -> 180"
                "1110 -> 190"
                "1192 -> 200"
                "1228 -> 210"
                "1275 -> 220"
                "1322 -> 230"
                "1398 -> 240"
                "1430 -> 250"
                "1477 -> 260"
                "1560 -> 270"
                "1608 -> 280"
                "1640 -> 290"
                "1685 -> 300"
              ];
            }
          ];
        })
      ];

    output = [
      {
        platform = "ledc";
        id = "mora_pump1_pwm";
        pin = 3;
        frequency = "25000 Hz";
        min_power = "30%";
        max_power = "100%";
        zero_means_zero = true;
      }
      {
        platform = "ledc";
        id = "mora_pump2_pwm";
        pin = 4;
        frequency = "25000 Hz";
        min_power = "30%";
        max_power = "100%";
        zero_means_zero = true;
      }
      {
        platform = "template";
        id = "mora_pumps_pwm";
        type = "float";
        write_action = [
          {
            lambda = ''
              id(mora_pump1_pwm).set_level(state);
              id(mora_pump2_pwm).set_level(state);
            '';
          }
        ];
      }
      {
        platform = "ledc";
        id = "mora_fans_pwm";
        pin = 8;
        frequency = "25000 Hz";
        min_power = "30%";
        max_power = "100%";
        zero_means_zero = true;
      }
    ];

    fan = [
      {
        platform = "speed";
        id = "mora_pumps";
        name = "Mora Pumps";
        output = "mora_pumps_pwm";
        restore_mode = "RESTORE_DEFAULT_ON";
      }
      {
        platform = "speed";
        id = "mora_fan1";
        name = "Mora Fan 1";
        output = "mora_fans_pwm";
        restore_mode = "RESTORE_DEFAULT_ON";
      }
    ];

    interval = [
      {
        interval = "15s";
        "then" = [
          {
            lambda = ''
              const bool global_max = id(ha_max_perf_all).has_state() && id(ha_max_perf_all).state;
              const auto mode = id(cooling_mode).state;
              if (global_max || mode == "Max") {
                auto fan_call = id(mora_fan1).turn_on();
                fan_call.set_speed(100);
                fan_call.perform();
                auto pump_call = id(mora_pumps).turn_on();
                pump_call.set_speed(100);
                pump_call.perform();
                return;
              }

              if (mode != "Auto") {
                return;
              }

              const bool t1_ok = id(ntc1_temp).has_state() && !isnan(id(ntc1_temp).state);
              const bool t2_ok = id(ntc2_temp).has_state() && !isnan(id(ntc2_temp).state);

              float t_avg = NAN;
              if (t1_ok && t2_ok) {
                t_avg = (id(ntc1_temp).state + id(ntc2_temp).state) * 0.5f;
              } else if (t1_ok) {
                t_avg = id(ntc1_temp).state;
              } else if (t2_ok) {
                t_avg = id(ntc2_temp).state;
              }

              int target = 100;  // fail-safe if both probes invalid
              if (!isnan(t_avg)) {
                struct Point { float t; float s; };
                static const Point curve[] = {
                  {28.0f, 30.0f},
                  {30.0f, 35.0f},
                  {32.0f, 45.0f},
                  {34.0f, 60.0f},
                  {36.0f, 75.0f},
                  {40.0f, 100.0f},
                };
                const size_t n = sizeof(curve) / sizeof(curve[0]);
                float speed = curve[n - 1].s;
                if (t_avg <= curve[0].t) {
                  speed = curve[0].s;
                } else {
                  for (size_t i = 1; i < n; i++) {
                    if (t_avg <= curve[i].t) {
                      const float dt = curve[i].t - curve[i - 1].t;
                      const float ds = curve[i].s - curve[i - 1].s;
                      const float f = (t_avg - curve[i - 1].t) / dt;
                      speed = curve[i - 1].s + f * ds;
                      break;
                    }
                  }
                }
                target = (int) (speed + 0.5f);
              }

              if (target < 30) target = 30;
              if (target > 100) target = 100;

              int current = id(mora_auto_fan_speed_pct);
              if (current < 0 || current > 100) current = 35;
              const int max_step = 5;
              if (target > current + max_step) target = current + max_step;
              if (target < current - max_step) target = current - max_step;

              id(mora_auto_fan_speed_pct) = target;

              auto call = id(mora_fan1).turn_on();
              call.set_speed(target);
              call.perform();
            '';
          }
        ];
      }
    ];
  };
}
