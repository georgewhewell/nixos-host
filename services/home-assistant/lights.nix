{ config, pkgs, ... }:

{

  services.home-assistant.config = {
    adaptive_lighting = {
      lights = [
        "light.bedroom_filament_light"
        "light.hallway_ceiling_light"
        "light.office_ceiling_light"
      ];
    };
    scene = [
      {
        name = "zzz";
        entities =
          let
            state = {
              state = "off";
              attributes = {
                brightness = 0;
              };
            };
          in
          {
            "light.bedroom_filament_light" = state;
            "light.hallway_ceiling_light" = state;
            "light.office_ceiling_light" = state;
            "light.corner_huelight" = state;
            "light.signify_netherlands_b_v_lta005_huelight_2" = state;
            "light.signify_netherlands_b_v_lta005_huelight" = state;
          };
      }
    ];
    light = [
      {
        platform = "group";
        name = "Bedside lights";
        entities = [ "light.signify_netherlands_b_v_lta005_huelight_2" "light.signify_netherlands_b_v_lta005_huelight" ];
      }
    ];
    automation =
      let
        bigRemote = "6fa8c342c806f9ef3825248cfffb7694";
        cornerLight = "36817c816692e0485acaea87dbfd4e8e";
        mkMotionLight = { name, motionSensor, lightTarget, condition ? null }:
          {
            alias = "${name} Lights";
            use_blueprint = {
              path = "homeassistant/motion_light.yaml";
              input = {
                motion_entity = motionSensor;
                light_target.area_id = lightTarget;
              };
            };
            condition = condition;
          };
        mkRemoteToggle = { name, remote, lightTarget, action }:
          {
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
      in
      [
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
          })

        (mkMotionLight
          {
            name = "Bedroom";
            motionSensor = "binary_sensor.bedroom_motion_sensor_motion";
            lightTarget = "605ca1bb58e342d6b7aeb66364977d62";
            condition = [
              # Dont activate during nighttime
              {
                alias = "Not in bed";
                condition = "state";
                entity_id = "binary_sensor.withings_in_bed_george";
                state = "off";
              }
            ];
          })

        # Turn on and off with small remote
        (mkRemoteToggle
          {
            name = "bedroom_filament_light";
            remote = "ee6328afcb13fd25142e3745ea7697b5";
            lightTarget = "a6a9740d1a1b5212b8ba8ccd41840eed";
            action = "on";
          })

        (mkRemoteToggle
          {
            name = "bedroom_filament_light";
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
          alias = "Turn on living room light";
          mode = "single";
          trigger = {
            device_id = bigRemote;
            domain = "zha";
            platform = "device";
            type = "remote_button_short_press";
            subtype = "turn_on";
          };
          action = {
            device_id = cornerLight;
            type = "brightness_increase";
            entity_id = "light.corner_huelight";
            domain = "light";
          };
        }

        # Turn off corner light with big remote
        {
          alias = "Turn off living room light";
          mode = "single";
          trigger = {
            device_id = bigRemote;
            domain = "zha";
            platform = "device";
            type = "remote_button_short_press";
            subtype = "turn_off";
          };
          action = {
            type = "brightness_decrease";
            device_id = cornerLight;
            entity_id = "light.corner_huelight";
            domain = "light";
          };
        }

        # Lower brightness corner light with big remote
        {
          alias = "Lower brightness living room";
          mode = "single";
          trigger = {
            device_id = bigRemote;
            domain = "zha";
            platform = "device";
            type = "remote_button_long_press";
            subtype = "dim_down";
          };
          action = {
            device_id = cornerLight;
            type = "turn_off";
            entity_id = "light.corner_huelight";
            domain = "light";
          };
        }

        # Increase brightness corner light with big remote
        {
          alias = "Increase brightness living room";
          mode = "single";
          trigger = {
            device_id = bigRemote;
            domain = "zha";
            platform = "device";
            type = "remote_button_long_press";
            subtype = "dim_up";
          };
          action = {
            device_id = cornerLight;
            type = "turn_on";
            entity_id = "light.corner_huelight";
            domain = "light";
          };
        }

        # Set random colour on corner light
        {
          alias = "Lower brightness living room";
          mode = "single";
          trigger = {
            device_id = bigRemote;
            domain = "zha";
            platform = "device";
            type = "remote_button_long_press";
            subtype = "dim_up";
          };
          action = {
            device_id = cornerLight;
            type = "turn_on";
            entity_id = "light.corner_huelight";
            domain = "light";
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
            at = "20:00:00";
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
