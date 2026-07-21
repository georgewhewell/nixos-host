# Single source of truth for room-scoped Home Assistant entities and helpers.
#
# Consumed by:
#   - lights.nix    → light groups, adaptive_lighting list, motion automations
#   - lovelace.nix  → per-room dashboard sections and feature cards
#
# Data shape per room (see `rooms` below):
#   label       — display name (also the HA area_id, lowercased)
#   icon        — mdi icon for the dashboard tile
#   lights      — list of fixtures; each is either a single light or a synthesized group:
#                 { name, entity, adaptive ? false, group ? null }
#                 If `group` is a list of member entities, lights.nix will create a
#                 `platform = "group"` light with `entity` as the resulting entity_id.
#   motion      — { sensor, timeout ? 120, conditions ? [] } or null
#   climate     — { temperature?, humidity?, battery? } or null
#   mediaPlayer — entity_id of a media player in the room, or null
#   battery     — entity_id of an extra battery indicator (e.g. motion sensor), or null
#
# Top-level helpers expose the derived structures used by the consumers.
{lib}: let
  inherit (lib) attrValues concatLists concatMap filter mapAttrsToList optional optionals;

  georgeInBedEntity = "binary_sensor.withings_in_bed_george";

  # ── Rooms ────────────────────────────────────────────────────────────────
  rooms = {
    bedroom = {
      label = "Bedroom";
      icon = "mdi:bed";
      lights = [
        {
          name = "Bedside";
          entity = "light.bedside_lights";
          group = ["light.bedside_left_2" "light.bedside_right"];
        }
        {
          name = "Ceiling";
          entity = "light.bedroom_ceiling_2";
          adaptive = true;
        }
      ];
      # No bedroom motion sensor currently paired; original entity
      # `binary_sensor.bedroom_motion_sensor_motion` doesn't exist in HA.
      motion = null;
      climate = {
        temperature = "sensor.bedroom_temperature_2";
        humidity = "sensor.bedroom_humidity_2";
        battery = "sensor.bedroom_battery_2";
      };
      mediaPlayer = "media_player.bedroom_2";
    };

    office = {
      label = "Office";
      icon = "mdi:desk";
      lights = [{
        name = "All";
        entity = "light.office_lights";
        group = [
          "light.office_ceiling_3"
          "light.office_led_strip_2_office_led_strip_2"
          "light.office_led_strip_2_office_led_strip_3"
          "light.heltec_lora_v2_my_light"
          "light.esp32_c3_super_mini_1_my_light"
          "light.esp32_s3_nano_oled_onboard_led"
        ];
        adaptive = true;
      }];
      motion = {
        sensor = "binary_sensor.office_3";
        timeout = 1800;
      };
      climate = {
        temperature = "sensor.sideboard_temp_temperature";
        humidity = "sensor.sideboard_temp_humidity";
        battery = "sensor.sideboard_temp_battery";
      };
      battery = "sensor.office_battery_3";
    };

    livingRoom = {
      label = "Living Room";
      icon = "mdi:sofa";
      lights = [{
        name = "All";
        entity = "light.living_room_lights";
        group = ["light.corner_light" "light.hue_iris" "light.esp32_c3_super_mini_2_my_light"];
      }];
      motion = {
        sensor = "binary_sensor.presence";
      };
      climate = {
        temperature = "sensor.presence_temperature";
        humidity = "sensor.presence_humidity";
      };
      mediaPlayer = "media_player.living_room";
    };

    hallway = {
      label = "Hallway";
      icon = "mdi:door";
      lights = [{
        name = "Ceiling";
        entity = "light.hallway_ceiling";
        adaptive = true;
      }];
      motion = {
        sensor = "binary_sensor.front_door";
      };
    };

    kitchen = {
      label = "Kitchen";
      icon = "mdi:fridge";
      lights = [{
        name = "Mirror";
        entity = "light.mirror_light";
        adaptive = true;
      }];
      motion = {
        sensor = "binary_sensor.kitchen_door";
      };
      climate = {
        battery = "sensor.kitchen_door_battery";
      };
    };
  };

  # ── Mora watercooler (esp32-c6-poseidon) ─────────────────────────────────
  mora = {
    label = "Mora Watercooler";
    icon = "mdi:water-pump";
    coolingMode = "select.esp32_c6_poseidon_cooling_mode";
    fan = "fan.esp32_c6_poseidon_mora_fan_1";
    pumps = "fan.esp32_c6_poseidon_mora_pumps";
    sensors = {
      flowRate = "sensor.esp32_c6_poseidon_mora_flow_rate";
      pump1Rpm = "sensor.esp32_c6_poseidon_mora_pump_1_rpm";
      pump2Rpm = "sensor.esp32_c6_poseidon_mora_pump_2_rpm";
      fansRpm = "sensor.esp32_c6_poseidon_mora_fans_rpm";
      waterTempA = "sensor.esp32_c6_poseidon_ntc_1_temperature";
      waterTempB = "sensor.esp32_c6_poseidon_ntc_2_temperature";
      boardTemp = "sensor.esp32_c6_poseidon_lis3dh_temperature";
      power20v = "sensor.esp32_c6_poseidon_ina3221_channel_1_power";
      power12v = "sensor.esp32_c6_poseidon_ina3221_channel_2_power";
      power3v3 = "sensor.esp32_c6_poseidon_ina3221_channel_3_power";
      pdVoltage = "sensor.esp32_c6_poseidon_pd_contracted_voltage";
      pdCurrent = "sensor.esp32_c6_poseidon_pd_contracted_current";
    };
  };

  # ── Cerberus rack climate (esp32-c6-cerberus) ────────────────────────────
  cerberus = {
    label = "Cerberus (Server Rack)";
    icon = "mdi:server";
    fan = "fan.console_fan_speed";
    sensors = {
      fanRpm = "sensor.cerberus_speed";
      ahtTemp = "sensor.cerberus_aht_temperature";
      ahtHumidity = "sensor.cerberus_aht_humidity";
      bmpTemp = "sensor.cerberus_bmp280_temperature";
      bmpPressure = "sensor.cerberus_bmp280_pressure";
      internalTemp = "sensor.internal_temperature";
    };
  };

  # ── Mining hosts ─────────────────────────────────────────────────────────
  # Per-host cooling, Curve Optimizer, and xmrig switches. `null` means that
  # capability is not present. Curve Optimizer is deliberately per-host only:
  # unlike fan/XMRig state, it must not be restored globally across idle/load
  # power-domain transitions.
  miners = {
    label = "Mining";
    masters = {
      maxPerf = "input_boolean.max_perf_all";
      xmrig = "input_boolean.xmrig_all";
    };
    hosts = [
      { name = "trex";      maxPerf = "switch.trex_max_performance";      curveOpt = null;                               xmrig = "switch.trex_xmrig"; }
      { name = "strix-1";   maxPerf = null;                               curveOpt = "switch.strix_1_curve_optimizer";   xmrig = "switch.strix_1_xmrig"; }
      { name = "strix-2";   maxPerf = null;                               curveOpt = "switch.strix_2_curve_optimizer";   xmrig = "switch.strix_2_xmrig"; }
      { name = "strix-3";   maxPerf = null;                               curveOpt = "switch.strix_3_curve_optimizer";   xmrig = "switch.strix_3_xmrig"; }
      { name = "strix-4";   maxPerf = null;                               curveOpt = "switch.strix_4_curve_optimizer";   xmrig = "switch.strix_4_xmrig"; }
      { name = "cerberus";  maxPerf = "switch.cerberus_max_performance";  curveOpt = null;                               xmrig = null; }
      { name = "fuckup";    maxPerf = null;                               curveOpt = null;                               xmrig = "switch.fuckup_xmrig"; }
      { name = "air";       maxPerf = null;                               curveOpt = null;                               xmrig = "switch.air_xmrig"; }
      { name = "mac";       maxPerf = null;                               curveOpt = null;                               xmrig = "switch.mac_xmrig"; }
      { name = "mbp";       maxPerf = null;                               curveOpt = null;                               xmrig = "switch.mbp_xmrig"; }
      { name = "goblin";    maxPerf = null;                               curveOpt = null;                               xmrig = "switch.goblin_xmrig"; }
    ];
  };

  # ── Derived structures for consumers ─────────────────────────────────────

  allFixtures = concatMap (room: room.lights) (attrValues rooms);
  allLightEntities = map (fixture: fixture.entity) allFixtures;

  # Light groups to synthesize as `platform = "group"`. Entity_id is derived
  # from the fixture's `entity` (must be "light.<key>").
  lightGroups =
    map
    (f: {
      name = f.entity;
      entities = f.group;
    })
    (filter (f: f ? group && f.group != null) allFixtures);

  # Entities to feed into adaptive_lighting.
  adaptiveLights =
    map (f: f.entity) (filter (f: f.adaptive or false) allFixtures);

  # Motion-light automations, derived from each room with `motion` set.
  motionAutomations =
    mapAttrsToList
    (_key: room: {
      alias = "${room.label} Lights";
      use_blueprint = {
        path = "homeassistant/motion_light.yaml";
        input = {
          motion_entity = room.motion.sensor;
          light_target.area_id = "{{ area_id('${room.label}') }}";
          no_motion_wait = room.motion.timeout or 120;
        };
      };
      condition =
        [
          {
            condition = "state";
            entity_id = georgeInBedEntity;
            state = "off";
          }
        ]
        ++ (room.motion.conditions or []);
    })
    (lib.filterAttrs (_: r: r.motion != null) rooms);
in {
  inherit rooms mora cerberus miners georgeInBedEntity;
  inherit allLightEntities lightGroups adaptiveLights motionAutomations;
}
