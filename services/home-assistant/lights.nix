{ config, pkgs, ... }:

{

  services.home-assistant.config = {
    # switch = [{
    #   platform = "flux";
    #   lights = [
    #     "light.bedroom_ceiling_light"
    #     "light.hallway_ceiling_light"
    #     "light.office_ceiling_light"
    #   ];
    #   start_time = "7:00";
    #   stop_time = "23:00";
    #   start_colortemp = 8000;
    #   sunset_colortemp = 2500;
    #   stop_colortemp = 1000;
    #   brightness = 100;
    #   disable_brightness_adjust = false;
    #   mode = "xy";
    #   transition = 30;
    #   interval = 60;
    # }];
    adaptive_lighting = {
      lights = [
        "light.bedroom_ceiling_light"
        "light.hallway_ceiling_light"
        "light.office_ceiling_light"
      ];
    };
    automation =
      [
        /* Turn on lights with motion sensors */
        {
          alias = "Hallway Lights";
          use_blueprint = {
            path = "homeassistant/motion_light.yaml";
            input = {
              motion_entity = "binary_sensor.front_door_motion_sense_motion";
              light_target.area_id = "hallway";
            };
          };
        }
        {
          alias = "Office Lights";
          use_blueprint = {
            path = "homeassistant/motion_light.yaml";
            input = {
              motion_entity = "binary_sensor.office_motion_sensor_motion";
              light_target.area_id = "office";
            };
          };
        }
        {
          alias = "Bedroom Lights";
          use_blueprint = {
            path = "homeassistant/motion_light.yaml";
            input = {
              motion_entity = "binary_sensor.bedroom_motion_sensor_motion";
              light_target.area_id = "605ca1bb58e342d6b7aeb66364977d62";
            };
          };
          condition = [
            # Dont activate during nighttime
            {
              alias = "Not in bed";
              condition = "state";
              entity_id = "binary_sensor.withings_in_bed_george";
              state = "off";
            }
          ];
        }

        /* Control bedroom light with small remote */
        {
          alias = "Small Remote Off";
          mode = "single";
          trigger = {
            device_id = "ee6328afcb13fd25142e3745ea7697b5";
            domain = "zha";
            type = "remote_button_short_press";
            platform = "device";
            subtype = "turn_off";
          };
          action = {
            type = "turn_off";
            device_id = "a6a9740d1a1b5212b8ba8ccd41840eed";
            entity_id = "light.bedroom_filament_light";
            domain = "light";
          };
        }
        {
          alias = "Small Remote On";
          mode = "single";
          trigger = {
            device_id = "ee6328afcb13fd25142e3745ea7697b5";
            domain = "zha";
            platform = "device";
            type = "remote_button_short_press";
            subtype = "turn_on";
          };
          action = {
            type = "turn_on";
            device_id = "a6a9740d1a1b5212b8ba8ccd41840eed";
            entity_id = "light.bedroom_filament_light";
            domain = "light";
          };
        }
      ];
    scene = [
      {
        name = "Zzz";
        entities =
          {
            "light.bedroom_ceiling_light" = "off";
            "light.hallway_ceiling_light" = "off";
            "light.office_ceiling_light" = "off";
            "light.bedroom_filament_light" = "off";
          };
      }
    ];
  };
}
