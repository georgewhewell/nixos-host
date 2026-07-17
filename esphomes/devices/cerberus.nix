{...}: {
  imports = [
    ../modules/common.nix
    ../modules/sonicare-bridge.nix
    ../modules/hardware/esp32-lan8720.nix
  ];

  esphome.settings = {
    esphome = {
      name = "cerberus";
      friendly_name = "cerberus";
    };

    i2c = [
      {
        sda = 4;
        scl = 2;
        scan = true;
        frequency = "100kHz";
        timeout = "100ms";
      }
    ];

    binary_sensor = [
      {
        platform = "homeassistant";
        id = "ha_max_perf_all";
        entity_id = "input_boolean.max_perf_all";
        internal = true;
        on_state."then" = [
          {"script.execute" = "sync_console_fan_output";}
        ];
      }
    ];

    globals = [
      {
        id = "local_max_performance_enabled";
        type = "bool";
        restore_value = "no";
        initial_value = "false";
      }
    ];

    output = [
      {
        platform = "ledc";
        id = "console_fan_speed";
        pin = 14;
        frequency = "25000 Hz";
        min_power = "40%";
      }
      {
        platform = "template";
        id = "proxy_output";
        type = "float";
        write_action = [
          {
            lambda = ''
              const bool global_max = id(ha_max_perf_all).has_state() && id(ha_max_perf_all).state;
              const bool effective_max = global_max || id(local_max_performance_enabled);
              float write_val =
                effective_max ? 1.0f :
                ((id(manual_fan_control).state) ?
                  id(manual_fan_control).speed / 100.0f :
                  state);
              id(console_fan_speed).set_level(write_val);
            '';
          }
        ];
      }
    ];

    fan = [
      {
        platform = "speed";
        id = "manual_fan_control";
        output = "proxy_output";
        name = "Console Fan Speed";
        restore_mode = "RESTORE_DEFAULT_ON";
        on_turn_off."then" = [
          {
            "fan.turn_on" = {
              id = "manual_fan_control";
              speed = 1;
            };
          }
        ];
      }
    ];

    script = [
      {
        id = "sync_console_fan_output";
        mode = "restart";
        "then" = [
          {
            lambda = ''
              const bool global_max = id(ha_max_perf_all).has_state() && id(ha_max_perf_all).state;
              const bool effective_max = global_max || id(local_max_performance_enabled);
              if (effective_max) {
                id(console_fan_speed).set_level(1.0f);
                return;
              }
              if (id(manual_fan_control).state) {
                auto fan_call = id(manual_fan_control).turn_on();
                fan_call.set_speed(id(manual_fan_control).speed);
                fan_call.perform();
              } else {
                auto fan_call = id(manual_fan_control).turn_on();
                fan_call.set_speed(1);
                fan_call.perform();
              }
            '';
          }
        ];
      }
    ];

    sensor = [
      {
        platform = "aht10";
        variant = "AHT20";
        temperature.name = "AHT Temperature";
        humidity.name = "AHT Humidity";
        address = "0x38";
        update_interval = "10s";
      }
      {
        platform = "bmp280_i2c";
        temperature.name = "BMP280 Temperature";
        pressure.name = "BMP280 Pressure";
        address = "0x77";
        update_interval = "10s";
      }
      {
        platform = "pulse_counter";
        pin = {
          number = 12;
          mode = "INPUT_PULLUP";
        };
        unit_of_measurement = "RPM";
        filters = [
          {multiply = 0.5;}
        ];
        id = "cerberus_speed";
        name = "cerberus Speed";
        update_interval = "10s";
      }
    ];

    switch = [
      {
        platform = "template";
        id = "max_performance_mode";
        name = "Max Performance";
        optimistic = true;
        restore_mode = "ALWAYS_OFF";
        turn_on_action = [
          {lambda = "id(local_max_performance_enabled) = true;";}
          {"script.execute" = "sync_console_fan_output";}
        ];
        turn_off_action = [
          {lambda = "id(local_max_performance_enabled) = false;";}
          {"script.execute" = "sync_console_fan_output";}
        ];
      }
    ];

};
}
