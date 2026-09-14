{...}: let
  legJoints = [
    {
      id = "north_knee";
      label = "North Knee";
      jointType = "knee";
      groupInverted = true;
      pin = "GPIO10";
      platform = "ledc";
    }
    {
      id = "north_hip";
      label = "North Hip";
      jointType = "hip";
      pin = "GPIO20";
      platform = "ledc";
    }
    {
      id = "east_knee";
      label = "East Knee";
      jointType = "knee";
      pin = "GPIO7";
      platform = "ledc";
    }
    {
      id = "east_hip";
      label = "East Hip";
      jointType = "hip";
      pin = "GPIO8";
      platform = "software_servo_output";
    }
    {
      id = "south_knee";
      label = "South Knee";
      jointType = "knee";
      groupInverted = true;
      pin = "GPIO4";
      platform = "ledc";
    }
    {
      id = "south_hip";
      label = "South Hip";
      jointType = "hip";
      pin = "GPIO6";
      platform = "ledc";
    }
    {
      id = "west_knee";
      label = "West Knee";
      jointType = "knee";
      pin = "GPIO21";
      platform = "ledc";
    }
    {
      id = "west_hip";
      label = "West Hip";
      jointType = "hip";
      pin = "GPIO9";
      platform = "software_servo_output";
    }
  ];
  groupControls = [
    {
      id = "twist";
      label = "Twist";
      jointType = "hip";
      icon = "mdi:rotate-360";
    }
    {
      id = "raise_lower";
      label = "Raise or Lower";
      jointType = "knee";
      icon = "mdi:arrow-expand-vertical";
    }
  ];
  moveJointGroup = jointType:
    builtins.concatStringsSep "\n" (builtins.map (joint: let
        direction =
          if joint.groupInverted or false
          then "-1.0f"
          else "1.0f";
      in ''
        id(servo_${joint.id}).write(x / 100.0f * ${direction});
        id(servo_${joint.id}_position).publish_state(x * ${direction});
      '')
      (builtins.filter (joint: joint.jointType == jointType) legJoints));
  sweepJoint = joint: [
    {
      lambda = ''
        ESP_LOGI("servo_sweep", "Sweeping ${joint.label} (${joint.pin})");
        id(servo_${joint.id}).write(-1.0f);
      '';
    }
    {delay = "900ms";}
    {lambda = "id(servo_${joint.id}).write(1.0f);";}
    {delay = "900ms";}
    {lambda = "id(servo_${joint.id}).write(0.0f);";}
    {delay = "900ms";}
    {lambda = "id(servo_${joint.id}).detach();";}
    {delay = "300ms";}
  ];
  sweepLegJoints = builtins.concatLists (builtins.map sweepJoint legJoints);
in {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
  ];

  esphome.settings = {
    substitutions.name = "esp32-c3-super-mini-2";

    esphome = {
      name = "\${name}";
      friendly_name = "Quadruped Robot";
      area = "Office";
    };

    # Super Mini boards run hot at the default 20 dBm; RSSI is strong enough
    # here to use the fleet's existing lower-power setting.
    wifi.output_power = "8.5dB";

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

    external_components = [
      {
        source = {
          type = "local";
          path = "external-components";
        };
        components = ["software_servo_output"];
      }
    ];

    # The C3 has six LEDC channels. GPIO8 and GPIO9 use the two general-purpose
    # timers for interrupt-driven 50 Hz pulses; all outputs start detached.
    output = builtins.map (joint:
      {
        platform = joint.platform;
        id = "servo_pwm_${joint.id}";
        pin = joint.pin;
      }
      // (
        if joint.platform == "ledc"
        then {frequency = "50Hz";}
        else {}
      ))
    legJoints;

    servo =
      builtins.map (joint: {
        id = "servo_${joint.id}";
        output = "servo_pwm_${joint.id}";
        restore = false;
        auto_detach_time = "1s";
      })
      legJoints;

    number =
      (builtins.map (joint: {
          platform = "template";
          id = "servo_${joint.id}_position";
          name = "${joint.label} Position";
          icon = "mdi:angle-acute";
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
              lambda = "id(servo_${joint.id}).write(x / 100.0f);";
            }
          ];
        })
        legJoints)
      ++ (builtins.map (control: {
          platform = "template";
          id = "${control.id}_control";
          name = control.label;
          icon = control.icon;
          unit_of_measurement = "%";
          mode = "slider";
          min_value = -100;
          max_value = 100;
          step = 1;
          initial_value = 0;
          restore_value = false;
          optimistic = true;
          set_action = [
            {lambda = moveJointGroup control.jointType;}
          ];
        })
        groupControls);

    script = [
      {
        id = "sweep_leg_joints";
        mode = "restart";
        "then" = sweepLegJoints;
      }
    ];

    button = [
      {
        platform = "template";
        name = "Sweep Leg Joints";
        icon = "mdi:format-list-numbered";
        on_press."then" = [
          {"script.execute" = "sweep_leg_joints";}
        ];
      }
    ];

    sensor = [
      {
        # External 100k/100k divider: BAT+ -> 100k -> GPIO0 -> 100k -> GND.
        # ESPHome reports the ADC-pin voltage, so multiply by two for the cell.
        platform = "adc";
        pin = "GPIO0";
        id = "battery_voltage";
        name = "Battery Voltage";
        attenuation = "auto";
        update_interval = "10s";
        filters = [
          {multiply = 2.0;}
        ];
        device_class = "voltage";
        state_class = "measurement";
        unit_of_measurement = "V";
        accuracy_decimals = 2;
      }
    ];
  };
}
