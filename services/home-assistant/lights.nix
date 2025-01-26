{
  config,
  pkgs,
  ...
}: {
  services.home-assistant.config = {
    adaptive_lighting = {
      lights = [
        "light.bedroom_ceiling_light"
        "light.hallway_ceiling_light"
        "light.office_ceiling_light"
      ];
    };
    scene = [
      {
        name = "zzz";
        entities = let
          state = {
            state = "off";
            attributes = {
              brightness = 0;
            };
          };
        in {
          "light.bedroom_ceiling_light" = state;
          "light.hallway_ceiling_light" = state;
          "light.office_ceiling_light" = state;
          "light.corner_huelight" = state;
          "light.signify_netherlands_b_v_lta005_huelight_2" = state;
          "light.signify_netherlands_b_v_lta005_huelight" = state;
          "light.signify_netherlands_b_v_929002376201_light" = state;
        };
      }
    ];
    light = [
      {
        platform = "group";
        name = "Bedside lights";
        entities = ["light.signify_netherlands_b_v_lta005_huelight_2" "light.signify_netherlands_b_v_lta005_huelight"];
      }
      {
        platform = "group";
        name = "Living Room lights";
        entities = ["light.corner_huelight" "light.signify_netherlands_b_v_929002376201_light"]; # Add more living room lights here
      }
    ];
    automation = let
      bigRemote = "6fa8c342c806f9ef3825248cfffb7694";
      cornerLight = "36817c816692e0485acaea87dbfd4e8e";
      mkMotionLight = {
        name,
        motionSensor,
        lightTarget,
        no_motion_wait ? 120,
        condition ? null,
      }: {
        alias = "${name} Lights";
        use_blueprint = {
          path = "homeassistant/motion_light.yaml";
          input = {
            motion_entity = motionSensor;
            light_target.area_id = lightTarget;
            no_motion_wait = no_motion_wait;
          };
        };
        condition = condition;
      };
      mkRemoteToggle = {
        name,
        remote,
        lightTarget,
        action,
      }: {
        alias = "${name} ${action}";
        mode = "single";
        trigger = {
          device_id = remote;
          domain = "zha";
          type = "remote_button_short_press";
          platform = "device";
          subtype = "turn_${action}";
        };
        action = {
          type = "turn_${action}";
          device_id = lightTarget;
          entity_id = "light.${name}";
          domain = "light";
        };
      };
    in [
      # Turn on lights with motion sensors
      (mkMotionLight
        {
          name = "Hallway";
          motionSensor = "binary_sensor.front_door_motion_sense_motion";
          lightTarget = "hallway";
        })

      (mkMotionLight
        {
          name = "Office";
          motionSensor = "binary_sensor.office_motion_sensor_motion";
          lightTarget = "office";
          no_motion_wait = 1800;
        })

      (mkMotionLight
        {
          name = "Bedroom";
          motionSensor = "binary_sensor.bedroom_motion_sensor_motion";
          lightTarget = "605ca1bb58e342d6b7aeb66364977d62";
          condition = [
            # Don't activate when george in bed
            {
              alias = "Not in bed";
              condition = "state";
              entity_id = "binary_sensor.withings_in_bed_george";
              state = "off";
            }
          ];
        })

      (mkMotionLight
        {
          name = "Kitchen";
          motionSensor = "binary_sensor.kitchen_motion_motion";
          lightTarget = "7ae2ad8521d84fcd83e91a93c365b217";
        })

      (mkMotionLight
        {
          name = "Living Room";
          motionSensor = "binary_sensor.living_room_motion_motion";
          lightTarget = "6951e68390ee4c70bdf0a1096d5748cc";
        })

      # Turn on and off with small remote
      (mkRemoteToggle
        {
          name = "bedroom_ceiling_light";
          remote = "ee6328afcb13fd25142e3745ea7697b5";
          lightTarget = "a6a9740d1a1b5212b8ba8ccd41840eed";
          action = "on";
        })

      (mkRemoteToggle
        {
          name = "bedroom_ceiling_light";
          remote = "ee6328afcb13fd25142e3745ea7697b5";
          lightTarget = "a6a9740d1a1b5212b8ba8ccd41840eed";
          action = "off";
        })

      # Turn off all lights when small remote long pressed
      {
        alias = "Turn off all lights";
        trigger = {
          device_id = "ee6328afcb13fd25142e3745ea7697b5";
          domain = "zha";
          type = "remote_button_long_press";
          subtype = "dim_down";
          platform = "device";
        };
        action = {
          service = "scene.turn_on";
          target = {
            entity_id = "scene.zzz";
          };
          data = {
            transition = "2.5";
          };
        };
      }

      # Turn on corner light with big remote
      {
        alias = "Increase living room lights";
        mode = "single";
        trigger = {
          device_id = bigRemote;
          domain = "zha";
          platform = "device";
          type = "remote_button_short_press";
          subtype = "turn_on";
        };
        action = {
          service = "light.turn_on";
          target = {
            area_id = "{{ area_id('Living Room') }}";
          };
          data = {brightness_step_pct = 10;};
        };
      }

      {
        alias = "Dim living room lights";
        mode = "single";
        trigger = {
          device_id = bigRemote;
          domain = "zha";
          platform = "device";
          type = "remote_button_short_press";
          subtype = "turn_off";
        };
        action = {
          service = "light.turn_on";
          target = {
            area_id = "{{ area_id('Living Room') }}";
          };
          data = {brightness_step_pct = -10;};
        };
      }

      {
        alias = "Turn off living room lights";
        mode = "single";
        trigger = {
          device_id = bigRemote;
          domain = "zha";
          platform = "device";
          type = "remote_button_long_press";
          subtype = "dim_down";
        };
        action = {
          service = "light.turn_off";
          target = {
            area_id = "{{ area_id('Living Room') }}";
          };
        };
      }

      {
        alias = "Turn on living room lights";
        mode = "single";
        trigger = {
          device_id = bigRemote;
          domain = "zha";
          platform = "device";
          type = "remote_button_long_press";
          subtype = "dim_up";
        };
        action = {
          service = "light.turn_on";
          target = {
            area_id = "{{ area_id('Living Room') }}";
          };
        };
      }

      # Set random colour on corner light
      {
        alias = "Living Room Random Colour";
        mode = "single";
        trigger = {
          device_id = bigRemote;
          domain = "zha";
          platform = "device";
          type = "remote_button_short_press";
          subtype = "right";
        };
        action = {
          service = "light.turn_on";
          target = {
            area_id = "{{ area_id('Living Room') }}";
          };
          data = {
            hs_color = [
              "{{ range(360)|random }}"
              "{{ range(80,101)|random }}"
            ];
          };
        };
      }

      {
        description = "bedtime light";
        mode = "single";
        trigger = {
          platform = "time";
          at = "18:00:00";
        };
        action = [
          {
            service = "light.turn_on";
            data = {
              kelvin = 2000;
              brightness_pct = 1;
            };
            target = {
              entity_id = [
                "light.signify_netherlands_b_v_lta005_huelight_2"
                "light.signify_netherlands_b_v_lta005_huelight"
              ];
            };
          }
        ];
      }
    ];
  };
}
