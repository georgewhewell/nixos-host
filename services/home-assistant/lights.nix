{pkgs, lib, ...}: let
  areas = import ./areas.nix {inherit lib;};
  bedsideLights = "light.bedside_lights";
  nonBedsideLights = builtins.filter (entity: entity != bedsideLights) areas.allLightEntities;
in {
  services.home-assistant = {
    customComponents = with pkgs.home-assistant-custom-components; [adaptive_lighting];
    config = {
      adaptive_lighting = {
        lights = areas.adaptiveLights;
        # Daytime cap — full 100% is harsh, especially on the office ceiling.
        max_brightness = 90;
        min_brightness = 1;
        # Warmer night, cooler-but-not-blue day.
        max_color_temp = 5000;
        min_color_temp = 1900;
        # Sleep-mode targets (toggle via `switch.adaptive_lighting_sleep_mode_default`).
        sleep_brightness = 1;
        sleep_color_temp = 1500;
        # Start the ramps 30 min outside actual sun events so the room is
        # already in the right place by the time it matters.
        sunrise_offset = -1800;
        sunset_offset = 1800;
        # Pick up physical-switch and Zigbee-remote changes (not just HA service calls).
        detect_non_ha_changes = true;
        # Manual brightness override lapses after 30 min — keeps "I dimmed
        # it once" from disabling adaptive control for the rest of the day.
        autoreset_control_seconds = 1800;
        # For grouped lights: send brightness and colour as separate service
        # calls so members that only accept one of them still get updated.
        separate_turn_on_commands = true;
      };

      light =
        map
        (g: {
          platform = "group";
          # Synthesize the group's display name from the entity_id, stripping
          # the `light.` prefix and humanising underscores.
          name = lib.concatStringsSep " " (
            map (s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s)
            (lib.splitString "_" (lib.removePrefix "light." g.name))
          );
          entities = g.entities;
        })
        areas.lightGroups;

      # Rooms declaring several presence sensors: any member being `on` holds
      # the room occupied. device_class must be `motion` for the
      # motion_light blueprint's entity selector to accept the group.
      binary_sensor =
        map
        (g: {
          platform = "group";
          inherit (g) name entities;
          device_class = "motion";
        })
        areas.motionGroups;

      automation = let
        bigRemote = "6fa8c342c806f9ef3825248cfffb7694";
      in
        areas.motionAutomations
        ++ [
          # Bedroom remote — short-press up: layered turn-on
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
                # All off → turn on bedside at minimum
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
                    target.entity_id = "light.bedside_lights";
                    data = {
                      brightness_pct = 1;
                      color_temp_kelvin = 2000;
                      transition = 3;
                    };
                  };
                }
                # Bedside on, ceiling off → turn on ceiling
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
                    target.entity_id = "light.bedroom_ceiling_2";
                    data = {
                      brightness_pct = 1;
                      color_temp_kelvin = 2000;
                      transition = 3;
                    };
                  };
                }
              ];
              default = {
                service = "light.turn_on";
                target.entity_id = "light.bedside_lights";
                data = {
                  brightness_pct = 1;
                  color_temp_kelvin = 2000;
                  transition = 3;
                };
              };
            };
          }

          # Bedroom remote — short-press down: layered turn-off
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
                    target.entity_id = "light.bedroom_ceiling_2";
                    data.transition = 3;
                  };
                }
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
                    target.entity_id = "light.bedside_lights";
                    data.transition = 3;
                  };
                }
              ];
            };
          }

          # Bedroom remote — long-press up: brighten whichever is on
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
                {
                  conditions = [{
                    condition = "state";
                    entity_id = "light.bedroom_ceiling_2";
                    state = "on";
                  }];
                  sequence = {
                    service = "light.turn_on";
                    target.entity_id = "light.bedroom_ceiling_2";
                    data = {
                      brightness_step_pct = 10;
                      transition = 1;
                    };
                  };
                }
                {
                  conditions = [{
                    condition = "state";
                    entity_id = "light.bedside_lights";
                    state = "on";
                  }];
                  sequence = {
                    service = "light.turn_on";
                    target.entity_id = "light.bedside_lights";
                    data = {
                      brightness_step_pct = 10;
                      transition = 1;
                    };
                  };
                }
              ];
            };
          }

          # Bedroom remote — long-press down: dim, or zzz if already bright-low
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
              choose = [{
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
                  target.entity_id = "all";
                  data.transition = 10;
                };
              }];
              default = {
                service = "light.turn_on";
                target.entity_id = "light.bedside_lights";
                data = {
                  brightness_step_pct = -10;
                  transition = 1;
                };
              };
            };
          }

          # Big remote — living room control
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
              target.area_id = "{{ area_id('Living Room') }}";
              data.brightness_step_pct = 10;
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
              target.area_id = "{{ area_id('Living Room') }}";
              data.brightness_step_pct = -10;
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
              target.area_id = "{{ area_id('Living Room') }}";
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
              target.area_id = "{{ area_id('Living Room') }}";
            };
          }

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
              target.area_id = "{{ area_id('Living Room') }}";
              data.hs_color = [
                "{{ range(360)|random }}"
                "{{ range(80,101)|random }}"
              ];
            };
          }

          # Bedtime scene
          {
            alias = "Evening bedside lights";
            description = "bedtime light";
            mode = "single";
            trigger = {
              platform = "time";
              at = "18:00:00";
            };
            action = [{
              service = "light.turn_on";
              data = {
                color_temp_kelvin = 2000;
                brightness_pct = 5;
              };
              target.entity_id = [bedsideLights];
            }];
          }

          {
            alias = "George in bed";
            mode = "restart";
            trigger = {
              platform = "state";
              entity_id = areas.georgeInBedEntity;
              to = "on";
            };
            action = [
              {
                service = "light.turn_off";
                target.entity_id = nonBedsideLights;
                data.transition = 10;
              }
              {
                service = "light.turn_on";
                target.entity_id = [bedsideLights];
                data = {
                  color_temp_kelvin = 2000;
                  brightness_pct = 1;
                  transition = 10;
                };
              }
            ];
          }

          # ── Overnight brightness ceiling ───────────────────────────────
          # The bedroom is blocked outright (areas.nix `daytimeOnly`), but the
          # shared rooms keep working after dark at a capped brightness.
          # Capping via adaptive_lighting rather than per-automation means a
          # light switched on by hand is limited too, not just motion. An
          # explicit brightness change still wins, for `autoreset_control_seconds`.
          # Only fixtures flagged `adaptive` in areas.nix are governed by this.
          {
            alias = "Night dim: 20% ceiling from 22:00";
            trigger = {
              platform = "time";
              at = "22:00:00";
            };
            action = [
              {
                service = "adaptive_lighting.change_switch_settings";
                data = {
                  entity_id = "switch.adaptive_lighting_default";
                  # Reset everything else to the values configured above, so
                  # this is idempotent no matter what ran earlier.
                  use_defaults = "configuration";
                  max_brightness = 20;
                };
              }
            ];
          }
          {
            # Sleep mode drops to `sleep_brightness` (1%) and 1500K.
            alias = "Night dim: 1% after midnight";
            trigger = {
              platform = "time";
              at = "00:00:00";
            };
            action = [
              {
                service = "switch.turn_on";
                target.entity_id = "switch.adaptive_lighting_sleep_mode_default";
              }
            ];
          }
          {
            alias = "Restore daytime lighting at 07:00";
            trigger = {
              platform = "time";
              at = "07:00:00";
            };
            action = [
              {
                service = "switch.turn_off";
                target.entity_id = "switch.adaptive_lighting_sleep_mode_default";
              }
              {
                service = "adaptive_lighting.change_switch_settings";
                data = {
                  entity_id = "switch.adaptive_lighting_default";
                  use_defaults = "configuration";
                };
              }
            ];
          }
        ];
    };
  };
}
