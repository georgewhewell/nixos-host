{pkgs, ...}: {
  services.home-assistant = {
    customComponents = with pkgs.home-assistant-custom-components; [adaptive_lighting];
    config = {
      adaptive_lighting = {
        lights = [
          "light.bedroom_ceiling_2"
          "light.hallway_ceiling_light"
          "light.office_ceiling_light"
          "light.mirror_light"
        ];
      };
      light = [
        {
          platform = "group";
          name = "Bedside lights";
          entities = ["light.bedside_left_2" "light.bedside_right"];
        }
        {
          platform = "group";
          name = "Living Room lights";
          entities = ["light.corner_light" "light.hue_iris"];
        }
      ];
      automation = let
        bigRemote = "6fa8c342c806f9ef3825248cfffb7694";
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
            service = "light.turn_${action}";
            target = {
              area_id = lightTarget;
            };
          };
        };
      in [
        # Turn on lights with motion sensors
        (mkMotionLight
          {
            name = "Hallway";
            motionSensor = "binary_sensor.front_door";
            lightTarget = "{{ area_id('Hallway') }}";
          })

        (mkMotionLight
          {
            name = "Office";
            motionSensor = "binary_sensor.office_3";
            lightTarget = "{{ area_id('Office') }}";
            no_motion_wait = 1800;
          })

        (mkMotionLight
          {
            name = "Bedroom";
            motionSensor = "binary_sensor.bedroom_motion_sensor_motion";
            lightTarget = "bedroom";
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
            motionSensor = "binary_sensor.kitchen_door_4";
            lightTarget = "{{ area_id('Kitchen') }}";
          })

        (mkMotionLight
          {
            name = "Living Room";
            motionSensor = "binary_sensor.living_room_motion_motion";
            lightTarget = "{{ area_id('Living Room') }}";
          })

        # Bedroom remote controls
        {
          alias = "bedroom lights up";
          mode = "single";
          trigger = {
            device_id = "ee6328afcb13fd25142e3745ea7697b5";
            domain = "zha";
            type = "remote_button_short_press";
            platform = "device";
            subtype = "turn_on";
          };
          action = {
            choose = [
              # If all lights off, turn on bedside lights
              {
                conditions = [
                  {
                    condition = "state";
                    entity_id = "light.bedside_lights";
                    state = "off";
                  }
                  {
                    condition = "or";
                    conditions = [
                      {
                        condition = "state";
                        entity_id = "light.bedroom_ceiling_2";
                        state = "off";
                      }
                      {
                        condition = "state";
                        entity_id = "light.bedroom_ceiling_2";
                        state = "unavailable";
                      }
                    ];
                  }
                ];
                sequence = {
                  service = "light.turn_on";
                  target = {
                    entity_id = "light.bedside_lights";
                  };
                  data = {
                    brightness_pct = 1;
                    kelvin = 2000;
                    transition = 3;
                  };
                };
              }
              # If bedside on but ceiling off/unavailable, turn on ceiling
              {
                conditions = [
                  {
                    condition = "state";
                    entity_id = "light.bedside_lights";
                    state = "on";
                  }
                  {
                    condition = "or";
                    conditions = [
                      {
                        condition = "state";
                        entity_id = "light.bedroom_ceiling_2";
                        state = "off";
                      }
                      {
                        condition = "state";
                        entity_id = "light.bedroom_ceiling_2";
                        state = "unavailable";
                      }
                    ];
                  }
                ];
                sequence = {
                  service = "light.turn_on";
                  target = {
                    entity_id = "light.bedroom_ceiling_2";
                  };
                  data = {
                    brightness_pct = 1;
                    kelvin = 2000;
                    transition = 3;
                  };
                };
              }
            ];
            # Fallback: if no conditions match, just turn on bedside lights
            default = {
              service = "light.turn_on";
              target = {
                entity_id = "light.bedside_lights";
              };
              data = {
                brightness_pct = 1;
                kelvin = 2000;
                transition = 3;
              };
            };
          };
        }

        {
          alias = "bedroom lights down";
          mode = "single";
          trigger = {
            device_id = "ee6328afcb13fd25142e3745ea7697b5";
            domain = "zha";
            type = "remote_button_short_press";
            platform = "device";
            subtype = "turn_off";
          };
          action = {
            choose = [
              # If both on, turn off ceiling first
              {
                conditions = [
                  {
                    condition = "state";
                    entity_id = "light.bedside_lights";
                    state = "on";
                  }
                  {
                    condition = "state";
                    entity_id = "light.bedroom_ceiling_2";
                    state = "on";
                  }
                ];
                sequence = {
                  service = "light.turn_off";
                  target = {
                    entity_id = "light.bedroom_ceiling_2";
                  };
                  data = {
                    transition = 3;
                  };
                };
              }
              # If only bedside on, turn off bedside
              {
                conditions = [
                  {
                    condition = "state";
                    entity_id = "light.bedside_lights";
                    state = "on";
                  }
                  {
                    condition = "state";
                    entity_id = "light.bedroom_ceiling_2";
                    state = "off";
                  }
                ];
                sequence = {
                  service = "light.turn_off";
                  target = {
                    entity_id = "light.bedside_lights";
                  };
                  data = {
                    transition = 3;
                  };
                };
              }
            ];
          };
        }

        # Long up press increases brightness
        {
          alias = "bedroom lights brightness up";
          mode = "single";
          trigger = {
            device_id = "ee6328afcb13fd25142e3745ea7697b5";
            domain = "zha";
            type = "remote_button_long_press";
            platform = "device";
            subtype = "dim_up";
          };
          action = {
            choose = [
              # If ceiling light is on, brighten it
              {
                conditions = [
                  {
                    condition = "state";
                    entity_id = "light.bedroom_ceiling_2";
                    state = "on";
                  }
                ];
                sequence = {
                  service = "light.turn_on";
                  target = {
                    entity_id = "light.bedroom_ceiling_2";
                  };
                  data = {
                    brightness_step_pct = 10;
                    transition = 1;
                  };
                };
              }
              # Otherwise brighten bedside lights
              {
                conditions = [
                  {
                    condition = "state";
                    entity_id = "light.bedside_lights";
                    state = "on";
                  }
                ];
                sequence = {
                  service = "light.turn_on";
                  target = {
                    entity_id = "light.bedside_lights";
                  };
                  data = {
                    brightness_step_pct = 10;
                    transition = 1;
                  };
                };
              }
            ];
          };
        }

        # Long press down: dim or turn off all lights
        {
          alias = "bedroom long press down";
          trigger = {
            device_id = "ee6328afcb13fd25142e3745ea7697b5";
            domain = "zha";
            type = "remote_button_long_press";
            subtype = "dim_down";
            platform = "device";
          };
          action = {
            choose = [
              # If bedside lights are on and bright (>1%), run zzz scene
              {
                conditions = [
                  {
                    condition = "state";
                    entity_id = "light.bedside_lights";
                    state = "on";
                  }
                  {
                    condition = "numeric_state";
                    entity_id = "light.bedside_lights";
                    attribute = "brightness";
                    above = 2.55;
                  }
                ];
                sequence = {
                  service = "light.turn_off";
                  target = {
                    entity_id = "all";
                  };
                  data = {
                    transition = 10;
                  };
                };
              }
            ];
            # Default: dim the bedside lights
            default = {
              service = "light.turn_on";
              target = {
                entity_id = "light.bedside_lights";
              };
              data = {
                brightness_step_pct = -10;
                transition = 1;
              };
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
                  "light.bedside_lights"
                ];
              };
            }
          ];
        }
      ];
    };
  };
}
