/* LVGL v9.3 config for the claw ST7789 status display.
 *
 * Anything not set here falls back to the defaults in lv_conf_internal.h.
 * The panel is 240x240 RGB565; the app supplies its own tick and flush
 * callbacks and renders partial (dirty) areas only.
 */
#ifndef LV_CONF_H
#define LV_CONF_H

#define LV_COLOR_DEPTH 16

/* System libc handles allocation/string/printf — no builtin pool to size. */
#define LV_USE_STDLIB_MALLOC    LV_STDLIB_CLIB
#define LV_USE_STDLIB_STRING    LV_STDLIB_CLIB
#define LV_USE_STDLIB_SPRINTF   LV_STDLIB_CLIB

#define LV_USE_LOG 1
#define LV_LOG_LEVEL LV_LOG_LEVEL_WARN
#define LV_LOG_PRINTF 1

/* Montserrat 14 is on by default; the dashboard also uses 20 and 32. */
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_MONTSERRAT_32 1
#define LV_FONT_DEFAULT &lv_font_montserrat_14

#endif /* LV_CONF_H */
