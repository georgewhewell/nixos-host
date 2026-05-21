{...}: {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    # ../modules/wifi-idf-tuning.nix
  ];

  esphome.settings = {
    substitutions.name = "esp32-s3-nano-oled";

    esphome = {
      name = "\${name}";
      friendly_name = "\${name}";
    };

    esp32 = {
      variant = "esp32c3";
      framework.type = "esp-idf";
    };

    i2c = [
      {
        sda = "GPIO5";
        scl = "GPIO6";
        scan = true;
        frequency = "800kHz";
      }
    ];

    # ads1115 = [
    #   {address = "0x48";}
    # ];

    sensor = [
      # {
      #   platform = "ina3221";
      #   address = "0x40";
      #   update_interval = "10s";
      #   channel_1 = {
      #     shunt_resistance = "0.1 ohm";
      #     current.name = "INA3221 Channel 1 Current";
      #     power.name = "INA3221 Channel 1 Power";
      #     bus_voltage.name = "INA3221 Channel 1 Bus Voltage";
      #     shunt_voltage.name = "INA3221 Channel 1 Shunt Voltage";
      #   };
      #   channel_2 = {
      #     shunt_resistance = "0.1 ohm";
      #     current.name = "INA3221 Channel 2 Current";
      #     power.name = "INA3221 Channel 2 Power";
      #     bus_voltage.name = "INA3221 Channel 2 Bus Voltage";
      #     shunt_voltage.name = "INA3221 Channel 2 Shunt Voltage";
      #   };
      #   channel_3 = {
      #     shunt_resistance = "0.1 ohm";
      #     current.name = "INA3221 Channel 3 Current";
      #     power.name = "INA3221 Channel 3 Power";
      #     bus_voltage.name = "INA3221 Channel 3 Bus Voltage";
      #     shunt_voltage.name = "INA3221 Channel 3 Shunt Voltage";
      #   };
      # }
      # {
      #   platform = "mpu6050";
      #   address = "0x68";
      #   accel_x.name = "MPU6050 Accel X";
      #   accel_y.name = "MPU6050 Accel Y";
      #   accel_z.name = "MPU6050 Accel z";
      #   gyro_x.name = "MPU6050 Gyro X";
      #   gyro_y.name = "MPU6050 Gyro Y";
      #   gyro_z.name = "MPU6050 Gyro z";
      #   temperature.name = "MPU6050 Temperature";
      # }
      # {
      #   platform = "ads1115";
      #   multiplexer = "A2_GND";
      #   gain = 4.096;
      #   name = "NTC 1 ADC Voltage";
      #   id = "ntc1_adc";
      #   update_interval = "10s";
      # }
      # {
      #   platform = "resistance";
      #   sensor = "ntc1_adc";
      #   configuration = "DOWNSTREAM";
      #   resistor = "6.8kOhm";
      #   id = "ntc1_resistance";
      #   name = "NTC 1 Resistance";
      #   entity_category = "diagnostic";
      # }
      # {
      #   platform = "ntc";
      #   sensor = "ntc1_resistance";
      #   name = "NTC 1 Temperature";
      #   calibration = [
      #     "194.3kOhm -> -40°C"
      #     "10kOhm -> 25°C"
      #     "0.530kOhm -> 125°C"
      #   ];
      # }
      # {
      #   platform = "ads1115";
      #   multiplexer = "A3_GND";
      #   gain = 4.096;
      #   name = "NTC 2 ADC Voltage";
      #   id = "ntc2_adc";
      #   update_interval = "10s";
      # }
      # {
      #   platform = "resistance";
      #   sensor = "ntc2_adc";
      #   configuration = "DOWNSTREAM";
      #   resistor = "6.8kOhm";
      #   id = "ntc2_resistance";
      #   name = "NTC 2 Resistance";
      #   entity_category = "diagnostic";
      # }
      # {
      #   platform = "ntc";
      #   sensor = "ntc2_resistance";
      #   name = "NTC 2 Temperature";
      #   calibration = [
      #     "194.3kOhm -> -40°C"
      #     "10kOhm -> 25°C"
      #     "0.530kOhm -> 125°C"
      #   ];
      # }
      # {
      #   platform = "pulse_counter";
      #   pin = {
      #     number = "GPIO1";
      #     mode = "INPUT_PULLUP";
      #   };
      #   unit_of_measurement = "RPM";
      #   id = "mora_pump1_rpm";
      #   name = "MoRa Pump 1 RPM";
      #   update_interval = "10s";
      #   filters = [
      #     {multiply = 0.5;}
      #     {
      #       clamp = {
      #         min_value = 0;
      #         max_value = 5000;
      #       };
      #     }
      #   ];
      # }
      # {
      #   platform = "pulse_counter";
      #   pin = {
      #     number = "GPIO20";
      #     mode = "INPUT_PULLUP";
      #   };
      #   unit_of_measurement = "RPM";
      #   id = "mora_pump2_rpm";
      #   name = "MoRa Pump 2 RPM";
      #   update_interval = "10s";
      #   filters = [
      #     {multiply = 0.5;}
      #     {
      #       clamp = {
      #         min_value = 0;
      #         max_value = 5000;
      #       };
      #     }
      #   ];
      # }
      # {
      #   platform = "pulse_counter";
      #   pin = {
      #     number = "GPIO7";
      #     mode = "INPUT_PULLUP";
      #   };
      #   unit_of_measurement = "RPM";
      #   id = "mora_fans_rpm";
      #   name = "MoRa Fans RPM";
      #   update_interval = "10s";
      #   filters = [
      #     {multiply = 0.5;}
      #     {
      #       clamp = {
      #         min_value = 0;
      #         max_value = 5000;
      #       };
      #     }
      #   ];
      # }
      # {
      #   platform = "pulse_counter";
      #   pin = {
      #     number = "GPIO3";
      #     mode = "INPUT_PULLUP";
      #   };
      #   unit_of_measurement = "L/h";
      #   id = "mora_flow_rate";
      #   name = "MoRa Flow Rate";
      #   update_interval = "10s";
      #   filters = [
      #     {
      #       calibrate_linear = [
      #         "327 -> 40"
      #         "369 -> 50"
      #         "404 -> 60"
      #         "449 -> 70"
      #         "493 -> 80"
      #         "510 -> 90"
      #         "560 -> 100"
      #         "640 -> 110"
      #         "700 -> 120"
      #         "737 -> 130"
      #         "783 -> 140"
      #         "850 -> 150"
      #         "960 -> 160"
      #         "1034 -> 170"
      #         "1064 -> 180"
      #         "1110 -> 190"
      #         "1192 -> 200"
      #         "1228 -> 210"
      #         "1275 -> 220"
      #         "1322 -> 230"
      #         "1398 -> 240"
      #         "1430 -> 250"
      #         "1477 -> 260"
      #         "1560 -> 270"
      #         "1608 -> 280"
      #         "1640 -> 290"
      #         "1685 -> 300"
      #       ];
      #     }
      #   ];
      # }
    ];

    # output = [
    #   {
    #     platform = "ledc";
    #     id = "mora_pump1_pwm";
    #     pin = "GPIO0";
    #     frequency = "25000 Hz";
    #     min_power = "30%";
    #     max_power = "100%";
    #     zero_means_zero = true;
    #   }
    #   {
    #     platform = "ledc";
    #     id = "mora_pump2_pwm";
    #     pin = "GPIO21";
    #     frequency = "25000 Hz";
    #     min_power = "30%";
    #     max_power = "100%";
    #     zero_means_zero = true;
    #   }
    #   {
    #     platform = "ledc";
    #     id = "mora_fans_pwm";
    #     pin = "GPIO4";
    #     frequency = "25000 Hz";
    #     min_power = "30%";
    #     max_power = "100%";
    #     zero_means_zero = true;
    #   }
    # ];
  };
}
