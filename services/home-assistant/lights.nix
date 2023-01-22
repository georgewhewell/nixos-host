{ config, pkgs, ... }:

{

  services.home-assistant.config = {
    adaptive_lighting = {
      lights = [
        "light.bedroom_ceiling_light"
        "light.hallway_ceiling_light"
        "light.office_ceiling_light"
      ];
    };
    automation =
      let
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
      ];

  };
}
