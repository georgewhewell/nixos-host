{...}: {
  services.home-assistant.lovelaceConfig = {
    title = "Home";
    views = [
      {
        path = "default_view";
        title = "Home";
        cards = [
          {
            type = "entities";
            entities = [
              "sun.sun"
            ];
            title = "Sun";
          }
          {
            type = "vertical-stack";
            cards = [
              {
                type = "custom:valetudo-map-card";
                vacuum = "valetudo_roborock";
              }
              {
                type = "entities";
                entities = [
                  {entity = "vacuum.valetudo_roborock";}
                  {entity = "sensor.valetudo_roborock_battery_level";}
                  {
                    entity = "automation.start_roborock";
                    name = "Clean at Noon";
                  }
                  {entity = "select.valetudo_roborock_fan";}
                ];
                title = "Roborock";
              }
            ];
          }
          {
            type = "weather-forecast";
            entity = "weather.home";
          }
          {
            type = "entities";
            entities = [
              "switch.adaptive_lighting_adapt_brightness_default"
              "switch.adaptive_lighting_adapt_color_default"
              "switch.adaptive_lighting_sleep_mode_default"
              "switch.adaptive_lighting_default"
            ];
          }
          {
            type = "entities";
            entities = [
              {
                entity = "sensor.sideboard_temp_temperature";
                secondary_info = "none";
                name = "Sideboard Temperature";
              }
              {
                entity = "sensor.sideboard_temp_humidity";
                name = "Sideboard Humidity";
                secondary_info = "none";
              }
              {entity = "sensor.bedroom_temperature_2";}
              {entity = "sensor.bedroom_humidity_2";}
            ];
          }
          {
            type = "entities";
            entities = [
              {entity = "sensor.bme680_breath_voc_equivalent";}
              {entity = "sensor.bme680_co2_equivalent";}
              {entity = "sensor.bme680_humidity_2";}
              {entity = "sensor.bme680_pressure_2";}
              {entity = "sensor.bme680_temperature_2";}
              {entity = "sensor.bme680_iaq";}
              {entity = "sensor.bme680_iaq_accuracy";}
              {entity = "sensor.bme680_iaq_classification";}
              {entity = "fan.console_fan_speed";}
              {entity = "sensor.cerberus_speed";}
            ];
            state_color = true;
          }
          {
            type = "entities";
            entities = [
              "sensor.air_monitor_lite_2080_carbon_dioxide"
              "sensor.air_monitor_lite_2080_humidity"
              "sensor.air_monitor_lite_2080_pm10"
              "sensor.air_monitor_lite_2080_pm25"
              "sensor.air_monitor_lite_2080_temperature"
            ];
          }
          {
            type = "entities";
            entities = [
              {entity = "light.bedside_lights";}
              {
                entity = "light.living_room_lights";
                name = "Living Room";
                secondary_info = "none";
              }
              {entity = "light.hallway_ceiling";}
              {entity = "light.office_ceiling_3";}
              {entity = "light.bedroom_ceiling_2";}
              {
                entity = "light.mirror_light";
                name = "Kitchen";
              }
            ];
            title = "Lights";
            state_color = false;
            show_header_toggle = true;
          }
          {
            type = "grid";
            square = false;
            columns = 1;
            cards = [
              {
                type = "entities";
                entities = [
                  "fan.console_fan_speed"
                  "button.pid_climate_autotune"
                ];
                title = "Cerberus";
              }
              {
                type = "thermostat";
                entity = "climate.console_fan_thermostat";
                features = [
                  {
                    type = "climate-hvac-modes";
                    hvac_modes = [
                      "off"
                      "cool"
                    ];
                  }
                ];
              }
            ];
          }
        ];
      }
    ];
  };
}
