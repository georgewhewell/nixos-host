{ ... }: {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
  ];

  esphome.settings = {
    substitutions.name = "esp32-c3-super-mini-1";

    esphome = {
      name = "\${name}";
      friendly_name = "Living Room LED Strip";
      area = "Living Room";
    };

    esp32 = {
      board = "esp32-c3-devkitm-1";
      framework = {
        type = "esp-idf";
        version = "latest";
        sdkconfig_options = {
          CONFIG_HTTPD_MAX_REQ_HDR_LEN = "1024";
          CONFIG_HTTPD_MAX_URI_LEN = "512";
          CONFIG_HTTPD_MAX_RESP_HDR_LEN = "1024";
          CONFIG_ESP_MAIN_TASK_STACK_SIZE = "8192";
          CONFIG_FREERTOS_TIMER_TASK_STACK_DEPTH = "3072";
        };
      };
    };

    i2c = [
      {
        sda = "GPIO20";
        scl = "GPIO21";
        scan = true;
        frequency = "400kHz";
      }
    ];

    sensor = [
      {
        platform = "ina219";
        address = "0x40";
        shunt_resistance = "0.1 ohm";
        max_voltage = "15.0V";
        max_current = "3.2A";
        update_interval = "5s";
        bus_voltage = {
          name = "Bus Voltage";
          id = "ina219_bus_voltage";
        };
        shunt_voltage = {
          name = "Shunt Voltage";
          id = "ina219_shunt_voltage";
        };
        current = {
          name = "Current";
          id = "ina219_current";
        };
        power = {
          name = "Power";
          id = "ina219_power";
        };
      }

      {
        platform = "pulse_counter";
        id = "aux_motor_rpm";
        name = "Aux Motor RPM";
        pin = {
          number = "GPIO3";
          mode = {
            input = true;
            pullup = true;
          };
        };
        unit_of_measurement = "RPM";
        accuracy_decimals = 0;
        update_interval = "2s";
        count_mode = {
          rising_edge = "DISABLE";
          falling_edge = "INCREMENT";
        };
        internal_filter = "1us";
        # FG = 2 pulses per revolution (typical BLDC). Adjust `multiply` if
        # different: 1 ppr → 1.0, 3 ppr → 0.333.
        filters = [
          { multiply = 0.5; }
        ];
        total = {
          id = "aux_motor_tach_pulses";
          name = "Aux Motor Tach Pulses";
        };
      }
    ];

    binary_sensor = [
      {
        platform = "gpio";
        id = "water_presence";
        name = "Water Presence";
        device_class = "moisture";
        pin = {
          number = "GPIO10";
          mode = "INPUT_PULLUP";
        };
        filters = [
          # { invert = true; }
          { delayed_on_off = "50ms"; }
        ];
      }
    ];

    number = [
      {
        platform = "template";
        id = "valve_hold_duty";
        name = "Valve Hold Duty";
        unit_of_measurement = "%";
        mode = "slider";
        min_value = 0;
        max_value = 100;
        step = 1;
        initial_value = 10;
        restore_value = true;
        optimistic = true;
        set_action = [
          {
            lambda = ''
              if (id(output_valve).position > 0.5f) {
                id(seal_valve_pwm).set_level(x / 100.0f);
              }
            '';
          }
        ];
      }
      {
        platform = "template";
        id = "valve_pull_in_time";
        name = "Valve Pull-in Time";
        unit_of_measurement = "ms";
        mode = "slider";
        min_value = 0;
        max_value = 1000;
        step = 25;
        initial_value = 250;
        restore_value = true;
        optimistic = true;
      }
      {
        platform = "template";
        id = "valve_pull_in_duty";
        name = "Valve Pull-in Duty";
        unit_of_measurement = "%";
        mode = "slider";
        min_value = 0;
        max_value = 100;
        step = 1;
        initial_value = 100;
        restore_value = true;
        optimistic = true;
      }
      {
        platform = "template";
        id = "aux_motor_speed";
        name = "Aux Motor Speed";
        unit_of_measurement = "%";
        mode = "slider";
        min_value = -100;
        max_value = 100;
        step = 1;
        initial_value = 0;
        restore_value = false;
        optimistic = true;
        set_action = [
          {
            lambda = ''
              if (x == 0.0f) {
                id(aux_motor_pwm).turn_off();
                id(aux_motor_enable).turn_off();
                return;
              }

              if (x < 0.0f) {
                id(aux_motor_reverse).turn_on();
                id(aux_motor_pwm).set_level(-x / 100.0f);
              } else {
                id(aux_motor_reverse).turn_off();
                id(aux_motor_pwm).set_level(x / 100.0f);
              }
              id(aux_motor_enable).turn_on();
            '';
          }
        ];
      }
    ];

    output = [
      {
        platform = "ledc";
        id = "seal_valve_pwm";
        pin = "GPIO0";
        frequency = "25000 Hz";
      }
      # {
      #   platform = "ledc";
      #   id = "pwm2";
      #   pin = "GPIO9";
      #   frequency = "25000 Hz";
      # }
      {
        platform = "ledc";
        id = "aux_motor_pwm";
        pin = "GPIO4";
        frequency = "25000 Hz";
        inverted = true;
        # min_power = "0%";
        # max_power = "50%";
        # zero_means_zero = true;
      }
    ];

    valve = [
      {
        platform = "template";
        id = "output_valve";
        name = "Output Valve";
        device_class = "water";
        optimistic = true;
        open_action = [
          {
            lambda = ''
              id(seal_valve_pwm).set_level(id(valve_pull_in_duty).state / 100.0f);
              delay(static_cast<uint32_t>(id(valve_pull_in_time).state));
              id(seal_valve_pwm).set_level(id(valve_hold_duty).state / 100.0f);
            '';
          }
        ];
        close_action = [
          {
            "output.set_level" = {
              id = "seal_valve_pwm";
              level = "0%";
            };
          }
        ];
      }
    ];

    switch = [
      {
        platform = "gpio";
        id = "aux_motor_reverse";
        name = "Aux Motor Reverse";
        pin = "GPIO2";
        internal = true;
        restore_mode = "ALWAYS_OFF";
        # interlock = [ "aux_motor_brake" ];
      }
      {
        platform = "gpio";
        id = "aux_motor_enable";
        name = "Aux Motor Enable";
        pin = "GPIO1";
        internal = true;
        restore_mode = "ALWAYS_OFF";
        # interlock = [ "aux_motor_reverse" ];
      }
      # {
      #   platform = "pwm_output";
      #   id = "seal_valve_pwm";
      #   name = "Seal Valve";
      #   restore_mode = "ALWAYS_OFF";
      #   # interlock = [ "aux_motor_reverse" ];
      # }

    ];
  };
}
