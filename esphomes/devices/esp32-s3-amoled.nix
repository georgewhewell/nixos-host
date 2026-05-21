{
  lib,
  ...
}: let
  mkLabel = attrs: {label = attrs;};
  mkObj = attrs: {obj = attrs;};
  mkCard = {
    id,
    x,
    y,
    width,
    height,
    style ? "dash_card",
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
      }
      // {
        scrollable = false;
      });
  cardTitle = {
    text,
    x ? 14,
    y ? 12,
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
  ui = rec {
    screenW = 536;
    screenH = 240;
    margin = 8;
    gap = 8;
    panelX = margin;
    panelY = margin;
    panelW = screenW - (margin * 2);
    panelH = screenH - (margin * 2);
    heroH = 100;
    heroX = margin;
    heroY = margin;
    heroW = screenW - (margin * 2);
    rowY = heroY + heroH + gap;
    rowH = screenH - rowY - margin;
    cardW = 168; # (screenW - 2*margin - 2*gap) / 3
    card1X = margin;
    card2X = card1X + cardW + gap;
    card3X = card2X + cardW + gap;
  };
in {
  imports = [
    ../modules/common.nix
    ../modules/wifi.nix
    ../modules/wifi-idf-tuning.nix
    ../modules/hardware/lilygo-t-display-s3-amoled.nix
  ];

  esphome.settings = {
    substitutions = {
      name = "esp32-s3-amoled";
    };

    esphome = {
      name = "\${name}";
      friendly_name = "LilygoDisplay";
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
      buffer_size = "12%";
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
          shadow_color = "black";
          shadow_opa = "8%";
          shadow_width = 4;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
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
          id = "dash_strip_blue";
          bg_color = "dash_accent2";
          bg_opa = "85%";
          radius = 16;
          border_width = 0;
          shadow_color = "dash_accent2";
          shadow_opa = "35%";
          shadow_width = 8;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_strip_cyan";
          bg_color = "dash_accent";
          bg_opa = "85%";
          radius = 16;
          border_width = 0;
          shadow_color = "dash_accent";
          shadow_opa = "35%";
          shadow_width = 8;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_strip_green";
          bg_color = "dash_good";
          bg_opa = "85%";
          radius = 16;
          border_width = 0;
          shadow_color = "dash_good";
          shadow_opa = "30%";
          shadow_width = 8;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_strip_pink";
          bg_color = "dash_pink";
          bg_opa = "85%";
          radius = 16;
          border_width = 0;
          shadow_color = "dash_pink";
          shadow_opa = "30%";
          shadow_width = 8;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_strip_amber";
          bg_color = "dash_amber";
          bg_opa = "85%";
          radius = 16;
          border_width = 0;
          shadow_color = "dash_amber";
          shadow_opa = "30%";
          shadow_width = 8;
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
          id = "dash_led_pink";
          bg_color = "dash_pink";
          shadow_color = "dash_pink";
          shadow_opa = "40%";
          shadow_width = 10;
          shadow_spread = 0;
          shadow_ofs_x = 0;
          shadow_ofs_y = 0;
        }
        {
          id = "dash_led_amber";
          bg_color = "dash_amber";
          shadow_color = "dash_amber";
          shadow_opa = "40%";
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
              x = ui.heroX;
              y = ui.heroY;
              width = ui.heroW;
              height = ui.heroH;
              style = ["dash_card_base" "dash_glow_blue"];
              widgets = [
                (mkObj {
                  x = 14;
                  y = 12;
                  styles = ["dash_led_base" "dash_led_blue"];
                  scrollable = false;
                })
                (mkLabel {
                  x = 28;
                  y = 8;
                  text = "OVERVIEW";
                  styles = "dash_page_title";
                })
                (mkLabel {
                  align = "top_right";
                  x = -12;
                  y = 78;
                  text = "PAGE 1/4";
                  styles = "dash_caption";
                })
                (mkLabel {
                  id = "dash_clock_label";
                  align = "top_right";
                  x = -12;
                  y = 10;
                  text = "--:--:--";
                  styles = "dash_clock";
                })
                (mkLabel {
                  id = "dash_wifi_status_label";
                  x = 14;
                  y = 34;
                  text = "Wi-Fi: connecting";
                  styles = "dash_value_lg";
                })
                (mkLabel {
                  id = "dash_ip_status_label";
                  x = 14;
                  y = 56;
                  text = "IP: -";
                  styles = "dash_text_blue";
                })
                (mkLabel {
                  id = "dash_signal_label";
                  x = 14;
                  y = 78;
                  text = "Signal: -- dBm | --%";
                  styles = "dash_caption";
                })
              ];
            })
            (mkCard {
              id = "perf_card";
              x = ui.card1X;
              y = ui.rowY;
              width = ui.cardW;
              height = ui.rowH;
              style = ["dash_card_base" "dash_glow_cyan"];
              widgets = [
                (cardTitle { text = "PERF"; })
                (mkLabel {
                  id = "dash_fps_value_label";
                  x = 12;
                  y = 26;
                  text = "0";
                  styles = "dash_value_xl";
                })
                (mkLabel {
                  id = "dash_fps_avg_label";
                  x = 86;
                  y = 34;
                  text = "avg 0.0";
                  styles = "dash_caption";
                })
                (mkLabel {
                  id = "dash_perf_cpu_label";
                  x = 12;
                  y = 74;
                  text = "CPU: -- MHz";
                  styles = "dash_mono";
                })
                (mkLabel {
                  id = "dash_perf_loop_label";
                  x = 12;
                  y = 92;
                  text = "Loop: -- ms";
                  styles = "dash_mono";
                })
              ];
            })
            (mkCard {
              id = "memory_card";
              x = ui.card2X;
              y = ui.rowY;
              width = ui.cardW;
              height = ui.rowH;
              style = ["dash_card_base" "dash_glow_green"];
              widgets = [
                (cardTitle { text = "MEMORY"; })
                (cardCaption { text = "Heap"; x = 12; y = 34; })
                (mkLabel {
                  id = "dash_heap_free_label";
                  x = 70;
                  y = 32;
                  text = "-- KB";
                  styles = "dash_mono";
                })
                (cardCaption { text = "Block"; x = 12; y = 54; })
                (mkLabel {
                  id = "dash_heap_block_label";
                  x = 70;
                  y = 52;
                  text = "-- KB";
                  styles = "dash_mono";
                })
                (cardCaption { text = "PSRAM"; x = 12; y = 74; })
                (mkLabel {
                  id = "dash_psram_free_label";
                  x = 70;
                  y = 72;
                  text = "-- MB";
                  styles = "dash_text_green";
                })
                (cardCaption { text = "Loop"; x = 12; y = 94; })
                (mkLabel {
                  id = "dash_mem_loop_label";
                  x = 70;
                  y = 92;
                  text = "-- ms";
                  styles = "dash_mono";
                })
              ];
            })
            (mkCard {
              id = "system_card";
              x = ui.card3X;
              y = ui.rowY;
              width = ui.cardW;
              height = ui.rowH;
              style = ["dash_card_base" "dash_glow_pink"];
              widgets = [
                (cardTitle { text = "SYSTEM"; })
                (mkLabel {
                  id = "dash_uptime_label";
                  x = 12;
                  y = 34;
                  text = "Uptime: --h --m";
                  styles = "dash_mono";
                })
                (mkLabel {
                  id = "dash_temp_label";
                  x = 12;
                  y = 54;
                  text = "MCU Temp: -- C";
                  styles = "dash_mono";
                })
                (mkLabel {
                  x = 12;
                  y = 92;
                  text = "ESP32-S3 OLED";
                  styles = "dash_caption";
                })
              ];
            })
          ];
        })
        (mkPage {
          id = "page_network";
          widgets = [
            (mkCard {
              id = "p2_network_panel";
              x = ui.panelX;
              y = ui.panelY;
              width = ui.panelW;
              height = ui.panelH;
              style = ["dash_card_base" "dash_glow_cyan"];
              widgets = [
                (mkObj {
                  x = 16;
                  y = 12;
                  styles = ["dash_led_base" "dash_led_cyan"];
                  scrollable = false;
                })
                (mkLabel {
                  x = 30;
                  y = 8;
                  text = "NETWORK";
                  styles = "dash_page_title";
                })
                (mkLabel {
                  align = "top_right";
                  x = -14;
                  y = 30;
                  text = "PAGE 2/4";
                  styles = "dash_caption";
                })
                (mkLabel {
                  id = "p2_clock_label";
                  align = "top_right";
                  x = -14;
                  y = 10;
                  text = "--:--:--";
                  styles = "dash_clock";
                })
                (mkLabel {
                  id = "p2_wifi_state_label";
                  x = 18;
                  y = 38;
                  text = "Wi-Fi: offline";
                  styles = "dash_value_lg";
                })
                (mkLabel {
                  id = "p2_ssid_label";
                  x = 18;
                  y = 66;
                  text = "SSID: -";
                  styles = "dash_text_cyan";
                })
                (mkObj {
                  x = 18;
                  y = 100;
                  width = 484;
                  height = 1;
                  bg_color = "dash_accent";
                  bg_opa = "30%";
                  border_width = 0;
                  radius = 0;
                  scrollable = false;
                })
                (mkLabel {
                  id = "p2_ip_label";
                  x = 18;
                  y = 112;
                  text = "IP: -";
                  styles = "dash_value_xl";
                })
                (mkLabel {
                  id = "p2_signal_quality_label";
                  x = 18;
                  y = 150;
                  text = "Signal: unknown";
                  styles = "dash_value_lg";
                })
                (mkLabel {
                  id = "p2_signal_value_label";
                  x = 18;
                  y = 178;
                  text = "RSSI: -- dBm | --%";
                  styles = "dash_mono";
                })
                (mkLabel {
                  x = 18;
                  y = 204;
                  text = "host: esp32-s3-amoled.local | domain: .lan.satanic.link";
                  styles = "dash_caption";
                })
              ];
            })
          ];
        })
        (mkPage {
          id = "page_performance";
          widgets = [
            (mkCard {
              id = "p3_perf_panel";
              x = ui.panelX;
              y = ui.panelY;
              width = ui.panelW;
              height = ui.panelH;
              style = ["dash_card_base" "dash_glow_pink"];
              widgets = [
                (mkObj {
                  x = 16;
                  y = 12;
                  styles = ["dash_led_base" "dash_led_pink"];
                  scrollable = false;
                })
                (mkLabel {
                  x = 30;
                  y = 8;
                  text = "PERFORMANCE";
                  styles = "dash_page_title";
                })
                (mkLabel {
                  align = "top_right";
                  x = -14;
                  y = 30;
                  text = "PAGE 3/4";
                  styles = "dash_caption";
                })
                (mkLabel {
                  id = "p3_clock_label";
                  align = "top_right";
                  x = -14;
                  y = 10;
                  text = "--:--:--";
                  styles = "dash_clock";
                })
                (mkCard {
                  id = "p3_fps_card";
                  x = 16;
                  y = 40;
                  width = 212;
                  height = 168;
                  style = ["dash_card_base" "dash_glow_cyan"];
                  widgets = [
                    (cardTitle { text = "UI DRAW"; x = 12; y = 10; })
                    (mkLabel {
                      id = "p3_fps_label";
                      x = 12;
                      y = 38;
                      text = "0";
                      styles = "dash_value_huge";
                    })
                    (mkLabel {
                      x = 112;
                      y = 54;
                      text = "FPS";
                      styles = "dash_text_cyan";
                    })
                    (mkLabel {
                      id = "p3_fps_avg_label";
                      x = 12;
                      y = 108;
                      text = "avg 0.0";
                      styles = "dash_caption";
                    })
                    (mkLabel {
                      x = 12;
                      y = 132;
                      text = "LVGL draw completions/s";
                      styles = "dash_caption";
                    })
                  ];
                })
                (mkCard {
                  id = "p3_stats_card";
                  x = 244;
                  y = 40;
                  width = 260;
                  height = 168;
                  style = ["dash_card_base" "dash_glow_blue"];
                  widgets = [
                    (cardTitle { text = "RUNTIME"; x = 12; y = 10; })
                    (mkLabel {
                      id = "p3_cpu_label";
                      x = 12;
                      y = 38;
                      text = "CPU: -- MHz";
                      styles = "dash_value_lg";
                    })
                    (mkLabel {
                      id = "p3_loop_label";
                      x = 12;
                      y = 68;
                      text = "Loop: -- ms";
                      styles = "dash_value_lg";
                    })
                    (mkLabel {
                      id = "p3_frame_cost_label";
                      x = 12;
                      y = 98;
                      text = "Frame cost: -- ms";
                      styles = "dash_text_blue";
                    })
                    (mkLabel {
                      id = "p3_mem_line_label";
                      x = 12;
                      y = 130;
                      text = "Mem: -- KB | -- MB";
                      styles = "dash_caption";
                    })
                  ];
                })
              ];
            })
          ];
        })
        (mkPage {
          id = "page_system";
          widgets = [
            (mkCard {
              id = "p4_system_panel";
              x = ui.panelX;
              y = ui.panelY;
              width = ui.panelW;
              height = ui.panelH;
              style = ["dash_card_base" "dash_glow_green"];
              widgets = [
                (mkObj {
                  x = 16;
                  y = 12;
                  styles = ["dash_led_base" "dash_led_green"];
                  scrollable = false;
                })
                (mkLabel {
                  x = 30;
                  y = 8;
                  text = "SYSTEM";
                  styles = "dash_page_title";
                })
                (mkLabel {
                  align = "top_right";
                  x = -14;
                  y = 30;
                  text = "PAGE 4/4";
                  styles = "dash_caption";
                })
                (mkLabel {
                  id = "p4_clock_label";
                  align = "top_right";
                  x = -14;
                  y = 10;
                  text = "--:--:--";
                  styles = "dash_clock";
                })
                (mkCard {
                  id = "p4_thermal_card";
                  x = 16;
                  y = 40;
                  width = 240;
                  height = 168;
                  style = ["dash_card_base" "dash_glow_amber"];
                  widgets = [
                    (cardTitle { text = "THERMAL"; x = 12; y = 10; })
                    (mkLabel {
                      id = "p4_temp_label";
                      x = 12;
                      y = 38;
                      text = "--.- C";
                      styles = "dash_value_xl";
                    })
                    (mkLabel {
                      id = "p4_uptime_label";
                      x = 12;
                      y = 88;
                      text = "Uptime: --h --m";
                      styles = "dash_value_lg";
                    })
                    (mkLabel {
                      x = 12;
                      y = 124;
                      text = "ESP32-S3 / RM67162 AMOLED";
                      styles = "dash_caption";
                    })
                  ];
                })
                (mkCard {
                  id = "p4_memory_card";
                  x = 272;
                  y = 40;
                  width = 232;
                  height = 168;
                  style = ["dash_card_base" "dash_glow_green"];
                  widgets = [
                    (cardTitle { text = "MEMORY"; x = 12; y = 10; })
                    (cardCaption { text = "Heap"; x = 12; y = 38; })
                    (mkLabel {
                      id = "p4_heap_free_label";
                      x = 92;
                      y = 36;
                      text = "-- KB";
                      styles = "dash_mono";
                    })
                    (cardCaption { text = "Block"; x = 12; y = 60; })
                    (mkLabel {
                      id = "p4_heap_block_label";
                      x = 92;
                      y = 58;
                      text = "-- KB";
                      styles = "dash_mono";
                    })
                    (cardCaption { text = "PSRAM"; x = 12; y = 82; })
                    (mkLabel {
                      id = "p4_psram_label";
                      x = 92;
                      y = 80;
                      text = "-- MB";
                      styles = "dash_text_green";
                    })
                    (cardCaption { text = "Loop"; x = 12; y = 104; })
                    (mkLabel {
                      id = "p4_loop_label";
                      x = 92;
                      y = 102;
                      text = "-- ms";
                      styles = "dash_mono";
                    })
                    (mkLabel {
                      x = 12;
                      y = 132;
                      text = "debug: free/block/psram/loop/cpu";
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
          (mkLabelUpdate "dash_clock_label" "%s" [
            "id(homeassistant_time).now().is_valid() ? id(homeassistant_time).now().strftime(\"%a %H:%M:%S\").c_str() : \"time unavailable\""
          ])
          (mkLabelUpdate "p2_clock_label" "%s" [
            "id(homeassistant_time).now().is_valid() ? id(homeassistant_time).now().strftime(\"%a %H:%M:%S\").c_str() : \"time unavailable\""
          ])
          (mkLabelUpdate "p3_clock_label" "%s" [
            "id(homeassistant_time).now().is_valid() ? id(homeassistant_time).now().strftime(\"%a %H:%M:%S\").c_str() : \"time unavailable\""
          ])
          (mkLabelUpdate "p4_clock_label" "%s" [
            "id(homeassistant_time).now().is_valid() ? id(homeassistant_time).now().strftime(\"%a %H:%M:%S\").c_str() : \"time unavailable\""
          ])

          (mkLabelUpdate "dash_wifi_status_label" "Wi-Fi: %s" [
            "id(wifi_info_ssid).state.empty() ? \"offline\" : id(wifi_info_ssid).state.c_str()"
          ])
          (mkLabelUpdate "dash_ip_status_label" "IP: %s" [
            "id(wifi_info_ip_address).state.empty() ? \"-\" : id(wifi_info_ip_address).state.c_str()"
          ])
          (mkLabelUpdate "dash_signal_label" "Signal: %s | %.0f%% | %.0f dBm" [
            "id(wifi_signal_percent).has_state() ? (id(wifi_signal_percent).state >= 70.0f ? \"excellent\" : id(wifi_signal_percent).state >= 45.0f ? \"good\" : id(wifi_signal_percent).state >= 25.0f ? \"weak\" : \"poor\") : \"unknown\""
            "id(wifi_signal_percent).has_state() ? id(wifi_signal_percent).state : 0.0f"
            "id(wifi_signal_db).has_state() ? id(wifi_signal_db).state : 0.0f"
          ])

          (mkLabelUpdate "dash_fps_value_label" "%u" ["id(ui_fps_last)"])
          (mkLabelUpdate "dash_fps_avg_label" "avg %.1f" ["id(ui_fps_avg)"])
          (mkLabelUpdate "dash_perf_cpu_label" "CPU: %.0f MHz" [
            "id(dbg_cpu_hz).has_state() ? id(dbg_cpu_hz).state / 1000000.0f : 0.0f"
          ])
          (mkLabelUpdate "dash_perf_loop_label" "Loop: %.0f ms" [
            "id(dbg_loop_ms).has_state() ? id(dbg_loop_ms).state : 0.0f"
          ])
          (mkLabelUpdate "dash_heap_free_label" "%.0f KB" [
            "id(dbg_heap_free).has_state() ? id(dbg_heap_free).state / 1024.0f : 0.0f"
          ])
          (mkLabelUpdate "dash_heap_block_label" "%.0f KB" [
            "id(dbg_heap_block).has_state() ? id(dbg_heap_block).state / 1024.0f : 0.0f"
          ])
          (mkLabelUpdate "dash_psram_free_label" "%.1f MB" [
            "id(dbg_psram_free).has_state() ? id(dbg_psram_free).state / 1048576.0f : 0.0f"
          ])
          (mkLabelUpdate "dash_mem_loop_label" "%.0f ms" [
            "id(dbg_loop_ms).has_state() ? id(dbg_loop_ms).state : 0.0f"
          ])
          (mkLabelUpdate "dash_uptime_label" "Uptime: %dh %dm" [
            "id(system_uptime).has_state() ? ((int) id(system_uptime).state) / 3600 : 0"
            "id(system_uptime).has_state() ? ((((int) id(system_uptime).state) % 3600) / 60) : 0"
          ])
          (mkLabelUpdate "dash_temp_label" "MCU Temp: %.1f C" [
            "id(system_internal_temperature).has_state() ? id(system_internal_temperature).state : 0.0f"
          ])

          (mkLabelUpdate "p2_wifi_state_label" "Wi-Fi: %s" [
            "id(wifi_info_ssid).state.empty() ? \"offline\" : \"connected\""
          ])
          (mkLabelUpdate "p2_ssid_label" "SSID: %s" [
            "id(wifi_info_ssid).state.empty() ? \"-\" : id(wifi_info_ssid).state.c_str()"
          ])
          (mkLabelUpdate "p2_ip_label" "IP: %s" [
            "id(wifi_info_ip_address).state.empty() ? \"-\" : id(wifi_info_ip_address).state.c_str()"
          ])
          (mkLabelUpdate "p2_signal_quality_label" "Signal: %s" [
            "id(wifi_signal_percent).has_state() ? (id(wifi_signal_percent).state >= 70.0f ? \"excellent\" : id(wifi_signal_percent).state >= 45.0f ? \"good\" : id(wifi_signal_percent).state >= 25.0f ? \"weak\" : \"poor\") : \"unknown\""
          ])
          (mkLabelUpdate "p2_signal_value_label" "RSSI: %.0f dBm | %.0f%%" [
            "id(wifi_signal_db).has_state() ? id(wifi_signal_db).state : 0.0f"
            "id(wifi_signal_percent).has_state() ? id(wifi_signal_percent).state : 0.0f"
          ])

          (mkLabelUpdate "p3_fps_label" "%u" ["id(ui_fps_last)"])
          (mkLabelUpdate "p3_fps_avg_label" "avg %.1f fps" ["id(ui_fps_avg)"])
          (mkLabelUpdate "p3_cpu_label" "CPU: %.0f MHz" [
            "id(dbg_cpu_hz).has_state() ? id(dbg_cpu_hz).state / 1000000.0f : 0.0f"
          ])
          (mkLabelUpdate "p3_loop_label" "Loop: %.0f ms" [
            "id(dbg_loop_ms).has_state() ? id(dbg_loop_ms).state : 0.0f"
          ])
          (mkLabelUpdate "p3_frame_cost_label" "Frame cost: %.1f ms" [
            "id(ui_fps_avg) > 0.1f ? 1000.0f / id(ui_fps_avg) : 0.0f"
          ])
          (mkLabelUpdate "p3_mem_line_label" "Mem: %.0f KB | %.1f MB" [
            "id(dbg_heap_free).has_state() ? id(dbg_heap_free).state / 1024.0f : 0.0f"
            "id(dbg_psram_free).has_state() ? id(dbg_psram_free).state / 1048576.0f : 0.0f"
          ])

          (mkLabelUpdate "p4_temp_label" "%.1f C" [
            "id(system_internal_temperature).has_state() ? id(system_internal_temperature).state : 0.0f"
          ])
          (mkLabelUpdate "p4_uptime_label" "Uptime: %dh %dm" [
            "id(system_uptime).has_state() ? ((int) id(system_uptime).state) / 3600 : 0"
            "id(system_uptime).has_state() ? ((((int) id(system_uptime).state) % 3600) / 60) : 0"
          ])
          (mkLabelUpdate "p4_heap_free_label" "%.0f KB" [
            "id(dbg_heap_free).has_state() ? id(dbg_heap_free).state / 1024.0f : 0.0f"
          ])
          (mkLabelUpdate "p4_heap_block_label" "%.0f KB" [
            "id(dbg_heap_block).has_state() ? id(dbg_heap_block).state / 1024.0f : 0.0f"
          ])
          (mkLabelUpdate "p4_psram_label" "%.1f MB" [
            "id(dbg_psram_free).has_state() ? id(dbg_psram_free).state / 1048576.0f : 0.0f"
          ])
          (mkLabelUpdate "p4_loop_label" "%.0f ms" [
            "id(dbg_loop_ms).has_state() ? id(dbg_loop_ms).state : 0.0f"
          ])
        ];
      }
      {
        interval = "6s";
        startup_delay = "8s";
        "then" = [
          {
            "lvgl.page.next" = {
              animation = "MOVE_LEFT";
              time = "260ms";
            };
          }
        ];
      }
    ];
  };
}
