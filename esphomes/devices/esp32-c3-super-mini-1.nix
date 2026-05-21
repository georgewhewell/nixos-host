{...}: {
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
        max_voltage = "32.0V";
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
          number = "GPIO2";
          mode = {
            input = true;
            pullup = true;
          };
        };
        unit_of_measurement = "RPM";
        accuracy_decimals = 0;
        update_interval = "2s";
        # FG = 2 pulses per revolution (typical BLDC). Adjust `multiply` if
        # different: 1 ppr → 1.0, 3 ppr → 0.333.
        filters = [
          {multiply = 0.5;}
        ];
      }
    ];

    binary_sensor = [
      {
        platform = "gpio";
        id = "water_presence";
        name = "Water Presence";
        device_class = "moisture";
        # invert = true;
        pin = {
          number = "GPIO10";
          mode = "INPUT_PULLUP";
        };
        filters = [
          {delayed_on_off = "50ms";}
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
      #   id = "dc_motor_pwm";
      #   pin = "GPIO9";
      #   frequency = "25000 Hz";
      #   min_power = "0%";
      #   max_power = "50%";
      #   zero_means_zero = true;
      # }
      {
        platform = "ledc";
        id = "aux_motor_pwm";
        pin = "GPIO1";
        frequency = "25000 Hz";
        # min_power = "0%";
        # max_power = "50%";
        # zero_means_zero = true;
      }
    ];

    fan = [
      # {
      #   platform = "speed";
      #   id = "dc_motor";
      #   name = "DC Motor";
      #   output = "dc_motor_pwm";
      #   restore_mode = "RESTORE_DEFAULT_OFF";
      # }
      {
        platform = "speed";
        id = "aux_motor";
        name = "Aux Motor";
        output = "aux_motor_pwm";
        restore_mode = "RESTORE_DEFAULT_OFF";
      }
    ];

    switch = [
      {
        platform = "gpio";
        id = "aux_motor_reverse";
        name = "Aux Motor Reverse";
        pin = "GPIO3";
        restore_mode = "ALWAYS_OFF";
        interlock = ["aux_motor_brake"];
      }
      {
        platform = "gpio";
        id = "aux_motor_brake";
        name = "Aux Motor Brake";
        pin = "GPIO4";
        restore_mode = "ALWAYS_OFF";
        interlock = ["aux_motor_reverse"];
      }
    ];
  };
}
