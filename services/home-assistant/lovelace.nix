{lib, ...}: let
  areas = import ./areas.nix {inherit lib;};
  inherit (lib) attrValues filter mapAttrsToList optional optionals;

  # ── Card builders ────────────────────────────────────────────────────────

  # Tile card for a light fixture, with brightness/color popup on hover.
  lightTile = fixture: {
    type = "tile";
    entity = fixture.entity;
    name = fixture.name or null;
    features = [
      {type = "light-brightness";}
      {type = "light-color-temp";}
    ];
    features_position = "bottom";
    show_entity_picture = false;
    vertical = false;
  };

  # Compact tile (no expanded controls) — used for climate sensors etc.
  sensorTile = {entity, name ? null}: {
    type = "tile";
    entity = entity;
    name = name;
    vertical = false;
  };

  # Per-room section: light fixtures + climate + media if present.
  roomSection = _key: room: let
    climate = room.climate or null;
    motion = room.motion or null;
    mediaPlayer = room.mediaPlayer or null;
    battery = room.battery or null;
  in {
    type = "grid";
    column_span = 1;
    cards =
      [{
        type = "heading";
        heading = room.label;
        heading_style = "title";
        icon = room.icon;
      }]
      ++ map lightTile room.lights
      ++ optional (climate != null && climate ? temperature) (sensorTile {
        entity = climate.temperature;
        name = "Temperature";
      })
      ++ optional (climate != null && climate ? humidity) (sensorTile {
        entity = climate.humidity;
        name = "Humidity";
      })
      ++ optional (motion != null) (sensorTile {
        entity = motion.sensor;
        name = "Motion";
      })
      ++ optional (mediaPlayer != null) {
        type = "media-control";
        entity = mediaPlayer;
      }
      ++ optional (battery != null) (sensorTile {
        entity = battery;
        name = "Battery";
      })
      ++ optional (climate != null && climate ? battery) (sensorTile {
        entity = climate.battery;
        name = "Sensor Battery";
      });
  };

  # Mora watercooler card.
  moraSection = let
    s = areas.mora.sensors;
  in {
    type = "grid";
    column_span = 1;
    cards = [
      {
        type = "heading";
        heading = areas.mora.label;
        heading_style = "title";
        icon = areas.mora.icon;
      }
      {
        type = "tile";
        entity = areas.mora.coolingMode;
        name = "Cooling mode";
      }
      {
        type = "tile";
        entity = areas.mora.pumps;
        name = "Pumps";
      }
      {
        type = "tile";
        entity = areas.mora.fan;
        name = "Fans";
      }
      (sensorTile {entity = s.flowRate; name = "Flow";})
      (sensorTile {entity = s.waterTempA; name = "Water in";})
      (sensorTile {entity = s.waterTempB; name = "Water out";})
      (sensorTile {entity = s.pump1Rpm; name = "Pump 1 RPM";})
      (sensorTile {entity = s.pump2Rpm; name = "Pump 2 RPM";})
      (sensorTile {entity = s.fansRpm; name = "Fan RPM";})
      (sensorTile {entity = s.power20v; name = "20V power";})
      (sensorTile {entity = s.power12v; name = "12V power";})
      (sensorTile {entity = s.boardTemp; name = "Board temp";})
    ];
  };

  # Cerberus rack card.
  cerberusSection = let
    s = areas.cerberus.sensors;
  in {
    type = "grid";
    column_span = 1;
    cards = [
      {
        type = "heading";
        heading = areas.cerberus.label;
        heading_style = "title";
        icon = areas.cerberus.icon;
      }
      {
        type = "tile";
        entity = areas.cerberus.fan;
        name = "Rack fan";
      }
      (sensorTile {entity = s.fanRpm; name = "Fan RPM";})
      (sensorTile {entity = s.ahtTemp; name = "Air temp";})
      (sensorTile {entity = s.ahtHumidity; name = "Humidity";})
      (sensorTile {entity = s.bmpPressure; name = "Pressure";})
      (sensorTile {entity = s.internalTemp; name = "Board temp";})
    ];
  };

  # Mining grid: master toggles + per-host max-perf + xmrig.
  miningSection = let
    inherit (areas.miners) hosts masters;
    hostRow = host:
      [{
        type = "heading";
        heading = host.name;
        heading_style = "subtitle";
      }]
      ++ optional (host.maxPerf != null) {
        type = "tile";
        entity = host.maxPerf;
        name = "Max perf";
        icon = "mdi:fan";
      }
      ++ optional (host.xmrig != null) {
        type = "tile";
        entity = host.xmrig;
        name = "XMRig";
        icon = "mdi:pickaxe";
      };
  in {
    type = "grid";
    column_span = 2;
    cards =
      [
        {
          type = "heading";
          heading = areas.miners.label;
          heading_style = "title";
          icon = "mdi:pickaxe";
        }
        {
          type = "tile";
          entity = masters.maxPerf;
          name = "Max perf (all)";
          icon = "mdi:fan";
        }
        {
          type = "tile";
          entity = masters.xmrig;
          name = "XMRig (all)";
          icon = "mdi:pickaxe";
        }
      ]
      ++ lib.concatMap hostRow hosts;
  };

  # Overview section: who's home, weather, vacuum mini.
  overviewSection = {
    type = "grid";
    column_span = 1;
    cards = [
      {
        type = "heading";
        heading = "Home";
        heading_style = "title";
        icon = "mdi:home";
      }
      {
        type = "tile";
        entity = "person.grw";
        name = "George";
      }
      {
        type = "weather-forecast";
        entity = "weather.home";
        forecast_type = "daily";
        show_current = true;
        show_forecast = true;
      }
      {
        type = "tile";
        entity = "vacuum.valetudo_roborock";
        name = "Roborock";
        features = [{type = "vacuum-commands"; commands = ["start_pause" "return_home"];}];
      }
      (sensorTile {entity = "sensor.valetudo_roborock_battery_level"; name = "Vacuum battery";})
      (sensorTile {entity = "automation.start_roborock"; name = "Clean at noon";})
    ];
  };

  # Adaptive lighting controls.
  adaptiveLightingSection = {
    type = "grid";
    column_span = 1;
    cards = [
      {
        type = "heading";
        heading = "Adaptive Lighting";
        heading_style = "title";
        icon = "mdi:theme-light-dark";
      }
      {type = "tile"; entity = "switch.adaptive_lighting_default"; name = "Master";}
      {type = "tile"; entity = "switch.adaptive_lighting_adapt_brightness_default"; name = "Brightness";}
      {type = "tile"; entity = "switch.adaptive_lighting_adapt_color_default"; name = "Colour";}
      {type = "tile"; entity = "switch.adaptive_lighting_sleep_mode_default"; name = "Sleep mode";}
    ];
  };

  # Air-quality monitor (single hardware unit; not associated with a room).
  airQualitySection = {
    type = "grid";
    column_span = 1;
    cards = [
      {
        type = "heading";
        heading = "Air Quality";
        heading_style = "title";
        icon = "mdi:air-filter";
      }
      (sensorTile {entity = "sensor.air_monitor_lite_2080_carbon_dioxide"; name = "CO₂";})
      (sensorTile {entity = "sensor.air_monitor_lite_2080_pm25"; name = "PM2.5";})
      (sensorTile {entity = "sensor.air_monitor_lite_2080_pm10"; name = "PM10";})
      (sensorTile {entity = "sensor.air_monitor_lite_2080_temperature"; name = "Temperature";})
      (sensorTile {entity = "sensor.air_monitor_lite_2080_humidity"; name = "Humidity";})
    ];
  };
in {
  services.home-assistant.lovelaceConfig = {
    title = "Home";
    views = [{
      title = "Home";
      path = "home";
      type = "sections";
      max_columns = 3;
      sections =
        [overviewSection]
        ++ mapAttrsToList roomSection areas.rooms
        ++ [
          adaptiveLightingSection
          airQualitySection
          moraSection
          cerberusSection
          miningSection
        ];
    }];
  };
}
