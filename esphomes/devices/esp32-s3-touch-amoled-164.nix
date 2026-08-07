## Waveshare ESP32-S3-Touch-AMOLED-1.64 — replacement for the dead
## esp32-s3-amoled (Lilygo T-Display-S3-AMOLED). Same dashboard vocabulary,
## re-laid out for a 280x456 portrait panel. Tap a card (or wait 8s) to page.
{...}: let
  mkLabel = attrs: {label = attrs;};
  mkObj = attrs: {obj = attrs;};
  pageNext = {
    "lvgl.page.next" = {
      animation = "MOVE_LEFT";
      time = "260ms";
    };
  };
  mkCard = {
    id,
    x,
    y,
    width,
    height,
    style ? "dash_card_base",
    tapToPage ? false,
    widgets,
  }:
    mkObj ({
        inherit
          id
          x
          y
          width
          height
          widgets
          ;
        styles = style;
        scrollable = false;
      }
      // (
        if tapToPage
        then {on_click = [pageNext];}
        else {}
      ));
  cardTitle = {
    text,
    x ? 12,
    y ? 10,
  }:
    mkLabel {
      inherit text x y;
      styles = "dash_card_title";
    };
  cardCaption = {
    text,
    x,
    y,
  }:
    mkLabel {
      inherit text x y;
      styles = "dash_caption";
    };
  mkLabelUpdate = id: format: args: {
    "lvgl.label.update" = {
      inherit id;
      text = {
        inherit format args;
      };
    };
  };
  mkPage = {
    id,
    widgets,
  }: {
    inherit id widgets;
    bg_color = "dash_bg";
    bg_opa = "cover";
    scrollable = false;
  };
  clockLambda = "id(homeassistant_time).now().is_valid() ? id(homeassistant_time).now().strftime(\"%H:%M:%S\").c_str() : \"--:--:--\"";
  ui = rec {
    screenW = 280;
    screenH = 456;
    margin = 8;
    gap = 8;
    colX = margin;
    colW = screenW - (margin * 2); # 264
    panelY = margin;
    panelH = screenH - (margin * 2); # 440

    heroY = margin;
    heroH = 112;
    netY = heroY + heroH + gap; # 128
    netH = 112;
    perfY = netY + netH + gap; # 248
    perfH = 100;
    sysY = perfY + perfH + gap; # 356
    sysH = screenH - sysY - margin; # 92
  };
in {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
    ../modules/hardware/waveshare-esp32-s3-touch-amoled-164.nix
  ];

  esphome.settings = {
    substitutions = {
      name = "esp32-s3-touch-amoled-164";
    };

    esphome = {
      name = "\${name}";
      friendly_name = "AMOLED 1.64";
    };

    color = [
      {
        id = "dash_bg";
        hex = "000000";
      }
      {
        id = "dash_card_bg";
        hex = "05070A";
      }
      {
        id = "dash_text";
        hex = "F2F6FF";
      }
      {
        id = "dash_muted";
        hex = "91A2C2";
      }
      {
        id = "dash_accent";
        hex = "4CC9F0";
      }
      {
        id = "dash_accent2";
        hex = "4361EE";
      }
      {
        id = "dash_good";
        hex = "56E39F";
      }
      {
        id = "dash_pink";
        hex = "FF5DA2";
      }
      {
        id = "dash_amber";
        hex = "FFB703";
      }
      {
        id = "dash_border";
        hex = "182236";
      }
    ];

    debug = {
      id = "dashboard_debug";
      update_interval = "2s";
    };

    globals = [
      {
        id = "ui_draw_count";
        type = "uint32_t";
        restore_value = false;
        initial_value = "0";
      }
      {
        id = "ui_fps_last";
        type = "uint32_t";
        restore_value = false;
        initial_value = "0";
      }
      {
        id = "ui_fps_avg";
        type = "float";
        restore_value = false;
        initial_value = "0.0f";
      }
    ];

    sensor = [
      {
        platform = "debug";
        debug_id = "dashboard_debug";
        free = {
          id = "dbg_heap_free";
          name = "Heap Free";
          disabled_by_default = true;
        };
        block = {
          id = "dbg_heap_block";
          name = "Heap Largest Block";
          disabled_by_default = true;
        };
        psram = {
          id = "dbg_psram_free";
          name = "PSRAM Free";
          disabled_by_default = true;
        };
        loop_time = {
          id = "dbg_loop_ms";
          name = "Loop Time";
          disabled_by_default = true;
        };
        cpu_frequency = {
          id = "dbg_cpu_hz";
          name = "CPU Frequency";
          disabled_by_default = true;
        };
      }
    ];

    lvgl = {
      displays = ["s3_display"];
      touchscreens = ["s3_touch"];
      buffer_size = "25%";
      default_font = "montserrat_14";
      bg_color = "dash_bg";
      disp_bg_color = "dash_bg";
      page_wrap = true;
      theme = {
        obj = {
          border_width = 0;
          pad_all = 0;
          radius = 0;
          bg_opa = "cover";
        };
        label.text_color = "dash_text";
      };
      style_definitions = [
        {
          id = "dash_card_base";
          bg_color = "dash_card_bg";
          bg_opa = "cover";
          radius = 16;
          border_width = 1;
          border_color = "dash_border";
          pad_all = 0;
        }
        {
          id = "dash_glow_blue";
          border_color = "dash_accent2";
          outline_color = "dash_accent2";
          outline_width = 1;
          outline_pad = 1;
          outline_opa = "20%";
          shadow_color = "dash_accent2";
          shadow_opa = "20%";
          shadow_width = 14;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_glow_cyan";
          border_color = "dash_accent";
          outline_color = "dash_accent";
          outline_width = 1;
          outline_pad = 1;
          outline_opa = "20%";
          shadow_color = "dash_accent";
          shadow_opa = "22%";
          shadow_width = 14;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_glow_green";
          border_color = "dash_good";
          outline_color = "dash_good";
          outline_width = 1;
          outline_pad = 1;
          outline_opa = "18%";
          shadow_color = "dash_good";
          shadow_opa = "20%";
          shadow_width = 14;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_glow_pink";
          border_color = "dash_pink";
          outline_color = "dash_pink";
          outline_width = 1;
          outline_pad = 1;
          outline_opa = "18%";
          shadow_color = "dash_pink";
          shadow_opa = "18%";
          shadow_width = 14;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_glow_amber";
          border_color = "dash_amber";
          outline_color = "dash_amber";
          outline_width = 1;
          outline_pad = 1;
          outline_opa = "18%";
          shadow_color = "dash_amber";
          shadow_opa = "18%";
          shadow_width = 14;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_led_base";
          width = 8;
          height = 8;
          radius = "circle";
          border_width = 0;
          bg_opa = "cover";
        }
        {
          id = "dash_led_blue";
          bg_color = "dash_accent2";
          shadow_color = "dash_accent2";
          shadow_opa = "45%";
          shadow_width = 10;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_led_cyan";
          bg_color = "dash_accent";
          shadow_color = "dash_accent";
          shadow_opa = "45%";
          shadow_width = 10;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_led_green";
          bg_color = "dash_good";
          shadow_color = "dash_good";
          shadow_opa = "45%";
          shadow_width = 10;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_page_title";
          text_color = "dash_text";
          text_font = "montserrat_18";
          text_letter_space = 1;
        }
        {
          id = "dash_card_title";
          text_color = "dash_muted";
          text_font = "montserrat_14";
          text_letter_space = 1;
        }
        {
          id = "dash_clock";
          text_color = "dash_text";
          text_font = "montserrat_14";
        }
        {
          id = "dash_caption";
          text_color = "dash_muted";
          text_font = "montserrat_14";
        }
        {
          id = "dash_value_huge";
          text_color = "dash_text";
          text_font = "montserrat_40";
        }
        {
          id = "dash_value_xl";
          text_color = "dash_text";
          text_font = "montserrat_28";
        }
        {
          id = "dash_value_lg";
          text_color = "dash_text";
          text_font = "montserrat_18";
        }
        {
          id = "dash_mono";
          text_color = "dash_text";
          text_font = "montserrat_14";
        }
        {
          id = "dash_text_blue";
          text_color = "dash_accent2";
          text_font = "montserrat_18";
        }
        {
          id = "dash_text_cyan";
          text_color = "dash_accent";
          text_font = "montserrat_18";
        }
        {
          id = "dash_text_green";
          text_color = "dash_good";
          text_font = "montserrat_18";
        }
      ];
      on_draw_end = [
        {
          lambda = ''
            id(ui_draw_count) += 1;
          '';
        }
      ];
      pages = [
        (mkPage {
          id = "page_overview";
          widgets = [
            (mkCard {
              id = "hero_card";
              x = ui.colX;
              y = ui.heroY;
              width = ui.colW;
              height = ui.heroH;
              style = ["dash_card_base" "dash_glow_blue"];
              tapToPage = true;
              widgets = [
                (mkObj {
                  x = 14;
                  y = 16;
                  styles = ["dash_led_base" "dash_led_blue"];
                  scrollable = false;
                })
                (mkLabel {
                  x = 28;
                  y = 10;
                  text = "OVERVIEW";
                  styles = "dash_page_title";
                })
                (mkLabel {
                  id = "dash_clock_label";
                  x = 14;
                  y = 38;
                  text = "--:--:--";
                  styles = "dash_value_xl";
                })
                (mkLabel {
                  id = "dash_date_label";
                  x = 14;
                  y = 78;
                  text = "--";
                  styles = "dash_caption";
                })
                (mkLabel {
                  align = "top_right";
                  x = -12;
                  y = 84;
                  text = "1/3";
                  styles = "dash_caption";
                })
              ];
            })
            (mkCard {
              id = "net_card";
              x = ui.colX;
              y = ui.netY;
              width = ui.colW;
              height = ui.netH;
              style = ["dash_card_base" "dash_glow_cyan"];
              tapToPage = true;
              widgets = [
                (cardTitle {text = "NETWORK";})
                (mkLabel {
                  id = "dash_ip_label";
                  x = 12;
                  y = 32;
                  text = "IP: -";
                  styles = "dash_text_cyan";
                })
                (mkLabel {
                  id = "dash_ssid_label";
                  x = 12;
                  y = 58;
                  text = "SSID: -";
                  styles = "dash_mono";
                })
                (mkLabel {
                  id = "dash_signal_label";
                  x = 12;
                  y = 82;
                  text = "-- dBm | --%";
                  styles = "dash_caption";
                })
              ];
            })
            (mkCard {
              id = "perf_card";
              x = ui.colX;
              y = ui.perfY;
              width = ui.colW;
              height = ui.perfH;
              style = ["dash_card_base" "dash_glow_pink"];
              tapToPage = true;
              widgets = [
                (cardTitle {text = "UI DRAW";})
                (mkLabel {
                  id = "dash_fps_value_label";
                  x = 12;
                  y = 30;
                  text = "0";
                  styles = "dash_value_huge";
                })
                (mkLabel {
                  x = 92;
                  y = 48;
                  text = "FPS";
                  styles = "dash_text_cyan";
                })
                (mkLabel {
                  id = "dash_fps_avg_label";
                  x = 156;
                  y = 34;
                  text = "avg 0.0";
                  styles = "dash_caption";
                })
                (mkLabel {
                  id = "dash_loop_label";
                  x = 156;
                  y = 56;
                  text = "loop -- ms";
                  styles = "dash_caption";
                })
              ];
            })
            (mkCard {
              id = "sys_card";
              x = ui.colX;
              y = ui.sysY;
              width = ui.colW;
              height = ui.sysH;
              style = ["dash_card_base" "dash_glow_green"];
              tapToPage = true;
              widgets = [
                (cardTitle {text = "SYSTEM";})
                (mkLabel {
                  id = "dash_uptime_label";
                  x = 12;
                  y = 32;
                  text = "Uptime: --h --m";
                  styles = "dash_mono";
                })
                (mkLabel {
                  id = "dash_temp_label";
                  x = 12;
                  y = 56;
                  text = "MCU: --.- C | Batt: -.-- V";
                  styles = "dash_mono";
                })
              ];
            })
          ];
        })
        (mkPage {
          id = "page_network";
          widgets = [
            (mkCard {
              id = "p2_panel";
              x = ui.colX;
              y = ui.panelY;
              width = ui.colW;
              height = ui.panelH;
              style = ["dash_card_base" "dash_glow_cyan"];
              tapToPage = true;
              widgets = [
                (mkObj {
                  x = 16;
                  y = 16;
                  styles = ["dash_led_base" "dash_led_cyan"];
                  scrollable = false;
                })
                (mkLabel {
                  x = 30;
                  y = 10;
                  text = "NETWORK";
                  styles = "dash_page_title";
                })
                (mkLabel {
                  align = "top_right";
                  x = -14;
                  y = 12;
                  text = "2/3";
                  styles = "dash_caption";
                })
                (mkObj {
                  x = 16;
                  y = 44;
                  width = 232;
                  height = 1;
                  bg_color = "dash_accent";
                  bg_opa = "30%";
                  border_width = 0;
                  radius = 0;
                  scrollable = false;
                })
                (cardCaption {
                  text = "STATE";
                  x = 16;
                  y = 58;
                })
                (mkLabel {
                  id = "p2_state_label";
                  x = 16;
                  y = 78;
                  text = "offline";
                  styles = "dash_value_lg";
                })
                (cardCaption {
                  text = "SSID";
                  x = 16;
                  y = 112;
                })
                (mkLabel {
                  id = "p2_ssid_label";
                  x = 16;
                  y = 132;
                  text = "-";
                  styles = "dash_text_cyan";
                })
                (cardCaption {
                  text = "IP ADDRESS";
                  x = 16;
                  y = 166;
                })
                (mkLabel {
                  id = "p2_ip_label";
                  x = 16;
                  y = 186;
                  text = "-";
                  styles = "dash_value_xl";
                })
                (cardCaption {
                  text = "SIGNAL";
                  x = 16;
                  y = 232;
                })
                (mkLabel {
                  id = "p2_signal_quality_label";
                  x = 16;
                  y = 252;
                  text = "unknown";
                  styles = "dash_value_lg";
                })
                (mkLabel {
                  id = "p2_signal_value_label";
                  x = 16;
                  y = 280;
                  text = "-- dBm | --%";
                  styles = "dash_mono";
                })
                (mkObj {
                  x = 16;
                  y = 312;
                  width = 232;
                  height = 1;
                  bg_color = "dash_accent";
                  bg_opa = "30%";
                  border_width = 0;
                  radius = 0;
                  scrollable = false;
                })
                (mkLabel {
                  x = 16;
                  y = 328;
                  text = "host:";
                  styles = "dash_caption";
                })
                (mkLabel {
                  x = 16;
                  y = 348;
                  text = "esp32-s3-touch-amoled-164";
                  styles = "dash_mono";
                })
                (mkLabel {
                  x = 16;
                  y = 368;
                  text = ".lan.satanic.link";
                  styles = "dash_caption";
                })
                (mkLabel {
                  id = "p2_clock_label";
                  x = 16;
                  y = 404;
                  text = "--:--:--";
                  styles = "dash_clock";
                })
              ];
            })
          ];
        })
        (mkPage {
          id = "page_system";
          widgets = [
            (mkCard {
              id = "p3_panel";
              x = ui.colX;
              y = ui.panelY;
              width = ui.colW;
              height = ui.panelH;
              style = ["dash_card_base" "dash_glow_green"];
              tapToPage = true;
              widgets = [
                (mkObj {
                  x = 16;
                  y = 16;
                  styles = ["dash_led_base" "dash_led_green"];
                  scrollable = false;
                })
                (mkLabel {
                  x = 30;
                  y = 10;
                  text = "SYSTEM";
                  styles = "dash_page_title";
                })
                (mkLabel {
                  align = "top_right";
                  x = -14;
                  y = 12;
                  text = "3/3";
                  styles = "dash_caption";
                })
                (mkCard {
                  id = "p3_thermal_card";
                  x = 12;
                  y = 44;
                  width = 240;
                  height = 132;
                  style = ["dash_card_base" "dash_glow_amber"];
                  widgets = [
                    (cardTitle {text = "THERMAL / POWER";})
                    (mkLabel {
                      id = "p3_temp_label";
                      x = 12;
                      y = 34;
                      text = "--.- C";
                      styles = "dash_value_xl";
                    })
                    (mkLabel {
                      id = "p3_batt_label";
                      x = 12;
                      y = 76;
                      text = "Batt: -.-- V";
                      styles = "dash_value_lg";
                    })
                    (mkLabel {
                      id = "p3_uptime_label";
                      x = 12;
                      y = 102;
                      text = "Uptime: --h --m";
                      styles = "dash_caption";
                    })
                  ];
                })
                (mkCard {
                  id = "p3_memory_card";
                  x = 12;
                  y = 188;
                  width = 240;
                  height = 152;
                  style = ["dash_card_base" "dash_glow_green"];
                  widgets = [
                    (cardTitle {text = "MEMORY";})
                    (cardCaption {
                      text = "Heap";
                      x = 12;
                      y = 38;
                    })
                    (mkLabel {
                      id = "p3_heap_free_label";
                      x = 100;
                      y = 36;
                      text = "-- KB";
                      styles = "dash_mono";
                    })
                    (cardCaption {
                      text = "Block";
                      x = 12;
                      y = 62;
                    })
                    (mkLabel {
                      id = "p3_heap_block_label";
                      x = 100;
                      y = 60;
                      text = "-- KB";
                      styles = "dash_mono";
                    })
                    (cardCaption {
                      text = "PSRAM";
                      x = 12;
                      y = 86;
                    })
                    (mkLabel {
                      id = "p3_psram_label";
                      x = 100;
                      y = 84;
                      text = "-- MB";
                      styles = "dash_text_green";
                    })
                    (cardCaption {
                      text = "Loop";
                      x = 12;
                      y = 110;
                    })
                    (mkLabel {
                      id = "p3_loop_label";
                      x = 100;
                      y = 108;
                      text = "-- ms";
                      styles = "dash_mono";
                    })
                  ];
                })
                (mkCard {
                  id = "p3_perf_card";
                  x = 12;
                  y = 352;
                  width = 240;
                  height = 76;
                  style = ["dash_card_base" "dash_glow_pink"];
                  widgets = [
                    (cardTitle {text = "RUNTIME";})
                    (mkLabel {
                      id = "p3_cpu_label";
                      x = 12;
                      y = 34;
                      text = "CPU: -- MHz";
                      styles = "dash_mono";
                    })
                    (mkLabel {
                      id = "p3_frame_cost_label";
                      x = 12;
                      y = 54;
                      text = "Frame: --.- ms";
                      styles = "dash_caption";
                    })
                  ];
                })
              ];
            })
          ];
        })
      ];
    };

    interval = [
      {
        interval = "1s";
        startup_delay = "500ms";
        "then" = [
          {
            lambda = ''
              id(ui_fps_last) = id(ui_draw_count);
              id(ui_draw_count) = 0;
              id(ui_fps_avg) = id(ui_fps_avg) * 0.75f + ((float) id(ui_fps_last)) * 0.25f;
            '';
          }
          (mkLabelUpdate "dash_clock_label" "%s" [clockLambda])
          (mkLabelUpdate "p2_clock_label" "%s" [clockLambda])
          (mkLabelUpdate "dash_date_label" "%s" [
            "id(homeassistant_time).now().is_valid() ? id(homeassistant_time).now().strftime(\"%a %d %b\").c_str() : \"no time\""
          ])

          (mkLabelUpdate "dash_ip_label" "IP: %s" [
            "id(wifi_info_ip_address).state.empty() ? \"-\" : id(wifi_info_ip_address).state.c_str()"
          ])
          (mkLabelUpdate "dash_ssid_label" "SSID: %s" [
            "id(wifi_info_ssid).state.empty() ? \"-\" : id(wifi_info_ssid).state.c_str()"
          ])
          (mkLabelUpdate "dash_signal_label" "%.0f dBm | %.0f%%" [
            "id(wifi_signal_db).has_state() ? id(wifi_signal_db).state : 0.0f"
            "id(wifi_signal_percent).has_state() ? id(wifi_signal_percent).state : 0.0f"
          ])

          (mkLabelUpdate "dash_fps_value_label" "%u" ["id(ui_fps_last)"])
          (mkLabelUpdate "dash_fps_avg_label" "avg %.1f" ["id(ui_fps_avg)"])
          (mkLabelUpdate "dash_loop_label" "loop %.0f ms" [
            "id(dbg_loop_ms).has_state() ? id(dbg_loop_ms).state : 0.0f"
          ])

          (mkLabelUpdate "dash_uptime_label" "Uptime: %dh %dm" [
            "id(system_uptime).has_state() ? ((int) id(system_uptime).state) / 3600 : 0"
            "id(system_uptime).has_state() ? ((((int) id(system_uptime).state) % 3600) / 60) : 0"
          ])
          (mkLabelUpdate "dash_temp_label" "MCU: %.1f C | Batt: %.2f V" [
            "id(system_internal_temperature).has_state() ? id(system_internal_temperature).state : 0.0f"
            "id(battery_voltage).has_state() ? id(battery_voltage).state : 0.0f"
          ])

          (mkLabelUpdate "p2_state_label" "%s" [
            "id(wifi_info_ssid).state.empty() ? \"offline\" : \"connected\""
          ])
          (mkLabelUpdate "p2_ssid_label" "%s" [
            "id(wifi_info_ssid).state.empty() ? \"-\" : id(wifi_info_ssid).state.c_str()"
          ])
          (mkLabelUpdate "p2_ip_label" "%s" [
            "id(wifi_info_ip_address).state.empty() ? \"-\" : id(wifi_info_ip_address).state.c_str()"
          ])
          (mkLabelUpdate "p2_signal_quality_label" "%s" [
            "id(wifi_signal_percent).has_state() ? (id(wifi_signal_percent).state >= 70.0f ? \"excellent\" : id(wifi_signal_percent).state >= 45.0f ? \"good\" : id(wifi_signal_percent).state >= 25.0f ? \"weak\" : \"poor\") : \"unknown\""
          ])
          (mkLabelUpdate "p2_signal_value_label" "%.0f dBm | %.0f%%" [
            "id(wifi_signal_db).has_state() ? id(wifi_signal_db).state : 0.0f"
            "id(wifi_signal_percent).has_state() ? id(wifi_signal_percent).state : 0.0f"
          ])

          (mkLabelUpdate "p3_temp_label" "%.1f C" [
            "id(system_internal_temperature).has_state() ? id(system_internal_temperature).state : 0.0f"
          ])
          (mkLabelUpdate "p3_batt_label" "Batt: %.2f V" [
            "id(battery_voltage).has_state() ? id(battery_voltage).state : 0.0f"
          ])
          (mkLabelUpdate "p3_uptime_label" "Uptime: %dh %dm" [
            "id(system_uptime).has_state() ? ((int) id(system_uptime).state) / 3600 : 0"
            "id(system_uptime).has_state() ? ((((int) id(system_uptime).state) % 3600) / 60) : 0"
          ])
          (mkLabelUpdate "p3_heap_free_label" "%.0f KB" [
            "id(dbg_heap_free).has_state() ? id(dbg_heap_free).state / 1024.0f : 0.0f"
          ])
          (mkLabelUpdate "p3_heap_block_label" "%.0f KB" [
            "id(dbg_heap_block).has_state() ? id(dbg_heap_block).state / 1024.0f : 0.0f"
          ])
          (mkLabelUpdate "p3_psram_label" "%.1f MB" [
            "id(dbg_psram_free).has_state() ? id(dbg_psram_free).state / 1048576.0f : 0.0f"
          ])
          (mkLabelUpdate "p3_loop_label" "%.0f ms" [
            "id(dbg_loop_ms).has_state() ? id(dbg_loop_ms).state : 0.0f"
          ])
          (mkLabelUpdate "p3_cpu_label" "CPU: %.0f MHz" [
            "id(dbg_cpu_hz).has_state() ? id(dbg_cpu_hz).state / 1000000.0f : 0.0f"
          ])
          (mkLabelUpdate "p3_frame_cost_label" "Frame: %.1f ms" [
            "id(ui_fps_avg) > 0.1f ? 1000.0f / id(ui_fps_avg) : 0.0f"
          ])
        ];
      }
      {
        interval = "8s";
        startup_delay = "10s";
        "then" = [pageNext];
      }
    ];
  };
}
