/* claw ST7789 LVGL status display.
 *
 * The hardware interface (EPHY pad handoff, GPIO v2 control lines, ST7789
 * cold-start sequence, +80 row offset, big-endian RGB565 on the wire) is
 * copied from the proven picoclaw-lcd-test bring-up in the nanokvm repo.
 * On top of that, LVGL renders a small fleet-status dashboard with partial
 * (dirty-area) flushes, so steady-state SPI traffic is a few KB per update
 * instead of a 115 KB full frame.
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <linux/gpio.h>
#include <linux/spi/spidev.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "lvgl.h"

enum {
    LCD_WIDTH = 240,
    LCD_HEIGHT = 240,
    LCD_Y_OFFSET = 80,
    GPIO_DC_INDEX = 0,
    GPIO_RESET_INDEX = 1,
    GPIO_BACKLIGHT_INDEX = 2,
    /* 240 px x 40 rows x RGB565 per draw buffer, double buffered. */
    DRAW_BUF_ROWS = 40,
    DRAW_BUF_SIZE = LCD_WIDTH * DRAW_BUF_ROWS * 2,
};

static volatile sig_atomic_t stopping;

static int spi_fd = -1;
static int gpio_fd = -1;

static lv_obj_t *label_clock;
static lv_obj_t *label_uptime;
static lv_obj_t *label_load;
static lv_obj_t *label_mem;
static lv_obj_t *label_link;
static lv_obj_t *heartbeat;
static int heartbeat_on;

/* NIC rate sampling state. */
static uint64_t prev_rx_bytes;
static uint64_t prev_tx_bytes;

static void on_signal(int signo)
{
    (void)signo;
    stopping = 1;
}

static void die(const char *operation)
{
    fprintf(stderr, "claw-lcd-status: %s: %s\n", operation, strerror(errno));
    exit(EXIT_FAILURE);
}

static void sleep_ms(long milliseconds)
{
    struct timespec delay = {
        .tv_sec = milliseconds / 1000,
        .tv_nsec = (milliseconds % 1000) * 1000000L,
    };

    while (nanosleep(&delay, &delay) < 0 && errno == EINTR && !stopping)
        ;
}

/* --- hardware glue (verbatim from picoclaw-lcd-test) -------------------- */

static void route_spi1_to_ethernet_pads(void)
{
    enum {
        EPHY_REG_BASE = 0x03009000,
        EPHY_REG_SIZE = 0x1000,
    };
    int mem_fd = open("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC);
    volatile uint32_t *registers;
    uint32_t value;

    if (mem_fd < 0)
        die("open /dev/mem for PicoClaw SPI1 pad handoff");
    registers = mmap(NULL, EPHY_REG_SIZE, PROT_READ | PROT_WRITE,
                     MAP_SHARED, mem_fd, EPHY_REG_BASE);
    if (registers == MAP_FAILED)
        die("map PicoClaw EPHY registers");

#define EPHY_REGISTER(address) registers[((address) - EPHY_REG_BASE) / 4]
    /* Sipeed's PicoClaw boot code releases ETH_TXP/TXM/RXP/RXM from the
     * internal EPHY/top-pad path before their function-6 SPI1 mux can drive
     * the LCD. */
    EPHY_REGISTER(0x03009804) |= UINT32_C(1);
    value = EPHY_REGISTER(0x03009808);
    EPHY_REGISTER(0x03009808) = (value & ~UINT32_C(0x1f)) | UINT32_C(1);
    EPHY_REGISTER(0x03009800) |= UINT32_C(1) << 2;
    __sync_synchronize();
    sleep_ms(1);

    value = EPHY_REGISTER(0x0300907c);
    EPHY_REGISTER(0x0300907c) =
        (value & ~(UINT32_C(0x1f) << 8)) | (UINT32_C(5) << 8);
    value = EPHY_REGISTER(0x03009078);
    EPHY_REGISTER(0x03009078) =
        (value & ~UINT32_C(0xfff)) | UINT32_C(0xf00);
    EPHY_REGISTER(0x03009074) = UINT32_C(0x606);
    EPHY_REGISTER(0x03009070) = UINT32_C(0x606);
    __sync_synchronize();
#undef EPHY_REGISTER

    if (munmap((void *)registers, EPHY_REG_SIZE) < 0)
        die("unmap PicoClaw EPHY registers");
    close(mem_fd);
}

static void write_all(int fd, const void *buffer, size_t length)
{
    const uint8_t *cursor = buffer;

    while (length > 0) {
        ssize_t written = write(fd, cursor, length);

        if (written < 0) {
            if (errno == EINTR)
                continue;
            die("SPI write");
        }
        if (written == 0) {
            errno = EIO;
            die("short SPI write");
        }
        cursor += written;
        length -= (size_t)written;
    }
}

static void read_all(int fd, void *buffer, size_t length)
{
    uint8_t *cursor = buffer;

    while (length > 0) {
        ssize_t received = read(fd, cursor, length);

        if (received < 0) {
            if (errno == EINTR)
                continue;
            die("SPI read");
        }
        if (received == 0) {
            errno = EIO;
            die("short SPI read");
        }
        cursor += received;
        length -= (size_t)received;
    }
}

static void gpio_set(int line_fd, unsigned int index, int high)
{
    struct gpio_v2_line_values values = {
        .bits = high ? (UINT64_C(1) << index) : 0,
        .mask = UINT64_C(1) << index,
    };

    if (ioctl(line_fd, GPIO_V2_LINE_SET_VALUES_IOCTL, &values) < 0)
        die("set GPIO line");
}

static int request_control_lines(const char *gpiochip)
{
    int chip_fd = open(gpiochip, O_RDONLY | O_CLOEXEC);
    struct gpio_v2_line_request request = {0};

    if (chip_fd < 0)
        die("open GPIO chip");

    request.offsets[GPIO_DC_INDEX] = 28;
    request.offsets[GPIO_RESET_INDEX] = 27;
    request.offsets[GPIO_BACKLIGHT_INDEX] = 19;
    request.num_lines = 3;
    request.config.flags = GPIO_V2_LINE_FLAG_OUTPUT;
    request.config.num_attrs = 1;
    request.config.attrs[0].attr.id = GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES;
    /* D/C low, reset high, active-low backlight high (off). */
    request.config.attrs[0].attr.values =
        (UINT64_C(1) << GPIO_RESET_INDEX) |
        (UINT64_C(1) << GPIO_BACKLIGHT_INDEX);
    request.config.attrs[0].mask = UINT64_C(0x7);
    snprintf(request.consumer, sizeof(request.consumer), "claw-lcd-status");

    if (ioctl(chip_fd, GPIO_V2_GET_LINE_IOCTL, &request) < 0)
        die("request GPIOA19/A27/A28");
    close(chip_fd);
    return request.fd;
}

static void lcd_command(uint8_t command, const uint8_t *data,
                        size_t data_length)
{
    gpio_set(gpio_fd, GPIO_DC_INDEX, 0);
    write_all(spi_fd, &command, 1);
    if (data_length > 0) {
        gpio_set(gpio_fd, GPIO_DC_INDEX, 1);
        write_all(spi_fd, data, data_length);
    }
}

static void lcd_read_register(uint8_t command, uint8_t *data,
                              size_t data_length)
{
    gpio_set(gpio_fd, GPIO_DC_INDEX, 0);
    write_all(spi_fd, &command, 1);
    gpio_set(gpio_fd, GPIO_DC_INDEX, 1);
    read_all(spi_fd, data, data_length);
}

static void lcd_log_identity(void)
{
    uint8_t id[4] = {0};
    size_t index;

    lcd_read_register(0x04, id, sizeof(id)); /* RDDID */

    fputs("claw-lcd-status: ST7789 RDDID:", stdout);
    for (index = 0; index < sizeof(id); ++index)
        printf(" %02x", id[index]);
    fputc('\n', stdout);
    fflush(stdout);
}

static void lcd_reset(void)
{
    gpio_set(gpio_fd, GPIO_BACKLIGHT_INDEX, 1);
    gpio_set(gpio_fd, GPIO_RESET_INDEX, 1);
    sleep_ms(50);
    gpio_set(gpio_fd, GPIO_RESET_INDEX, 0);
    sleep_ms(50);
    gpio_set(gpio_fd, GPIO_RESET_INDEX, 1);
    sleep_ms(50);
}

static void lcd_init(void)
{
    const uint8_t porch_control[] = { 0x1f, 0x1f, 0x00, 0x33, 0x33 };
    const uint8_t madctl = 0xc0;
    const uint8_t pixel_format = 0x05;
    const uint8_t gate_control = 0x00;
    const uint8_t vcom = 0x36;
    const uint8_t lcm_control = 0x2c;
    const uint8_t vdv_vrh_enable = 0x01;
    const uint8_t vrh = 0x13;
    const uint8_t vdv = 0x20;
    const uint8_t frame_rate = 0x13;
    const uint8_t gate_control_2 = 0xa1;
    const uint8_t power_control[] = { 0xa4, 0xa1 };
    const uint8_t positive_gamma[] = {
        0xf0, 0x08, 0x0e, 0x09, 0x08, 0x04, 0x2f,
        0x33, 0x45, 0x36, 0x13, 0x12, 0x2a, 0x2d,
    };
    const uint8_t negative_gamma[] = {
        0xf0, 0x0e, 0x12, 0x0c, 0x0a, 0x15, 0x2e,
        0x32, 0x44, 0x39, 0x17, 0x18, 0x2b, 0x2f,
    };
    const uint8_t gate_control_3[] = { 0x1d, 0x00, 0x00 };

    /* Full PicoClaw cold-start sequence from Sipeed's first rvclaw driver. */
    lcd_reset();
    lcd_command(0x11, NULL, 0); /* SLPOUT */
    sleep_ms(120);
    lcd_command(0xb2, porch_control, sizeof(porch_control));
    lcd_command(0x36, &madctl, 1);
    lcd_command(0x3a, &pixel_format, 1);
    lcd_command(0xb7, &gate_control, 1);
    lcd_command(0xbb, &vcom, 1);
    lcd_command(0xc0, &lcm_control, 1);
    lcd_command(0xc2, &vdv_vrh_enable, 1);
    lcd_command(0xc3, &vrh, 1);
    lcd_command(0xc4, &vdv, 1);
    lcd_command(0xc6, &frame_rate, 1);
    lcd_command(0xd6, &gate_control_2, 1);
    lcd_command(0xd0, power_control, sizeof(power_control));
    lcd_command(0xe0, positive_gamma, sizeof(positive_gamma));
    lcd_command(0xe1, negative_gamma, sizeof(negative_gamma));
    lcd_command(0xe4, gate_control_3, sizeof(gate_control_3));
    lcd_command(0x21, NULL, 0); /* INVON */
    lcd_command(0x11, NULL, 0); /* SLPOUT */
    lcd_command(0x29, NULL, 0); /* DISPON */
    sleep_ms(100);
}

static int open_spi(const char *path, uint32_t speed)
{
    int fd = open(path, O_RDWR | O_CLOEXEC);
    uint8_t mode = SPI_MODE_0;
    uint8_t bits = 8;

    if (fd < 0)
        die("open SPI device");
    if (ioctl(fd, SPI_IOC_WR_MODE, &mode) < 0 ||
        ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
        /* spidev clamps this to the DTB's spi-max-frequency (10 MHz). */
        ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0)
        die("configure SPI device");
    return fd;
}

/* --- LVGL glue ----------------------------------------------------------- */

static void flush_cb(lv_display_t *display, const lv_area_t *area,
                     uint8_t *px_map)
{
    uint32_t width = (uint32_t)(area->x2 - area->x1 + 1);
    uint32_t height = (uint32_t)(area->y2 - area->y1 + 1);
    uint32_t pixels = width * height;
    uint16_t row_start = (uint16_t)(area->y1 + LCD_Y_OFFSET);
    uint16_t row_end = (uint16_t)(area->y2 + LCD_Y_OFFSET);
    uint8_t column[] = {
        (uint8_t)(area->x1 >> 8), (uint8_t)area->x1,
        (uint8_t)(area->x2 >> 8), (uint8_t)area->x2,
    };
    uint8_t row[] = {
        (uint8_t)(row_start >> 8), (uint8_t)row_start,
        (uint8_t)(row_end >> 8), (uint8_t)row_end,
    };
    uint16_t *px = (uint16_t *)px_map;
    uint32_t i;

    /* LVGL renders little-endian RGB565; the ST7789 wants big-endian. */
    for (i = 0; i < pixels; ++i)
        px[i] = (uint16_t)((px[i] >> 8) | (px[i] << 8));

    lcd_command(0x2a, column, sizeof(column)); /* CASET */
    lcd_command(0x2b, row, sizeof(row)); /* RASET */
    lcd_command(0x2c, NULL, 0); /* RAMWR */
    gpio_set(gpio_fd, GPIO_DC_INDEX, 1);
    write_all(spi_fd, px_map, pixels * 2);

    lv_display_flush_ready(display);
}

static uint32_t tick_get(void)
{
    struct timespec now;

    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint32_t)(now.tv_sec * 1000 + now.tv_nsec / 1000000);
}

/* --- status sampling ------------------------------------------------------ */

static void set_label(lv_obj_t *label, const char *text)
{
    const char *current = lv_label_get_text(label);

    if (current == NULL || strcmp(current, text) != 0)
        lv_label_set_text(label, text);
}

static void sample_clock(char *buffer, size_t size)
{
    time_t now = time(NULL);
    struct tm local;

    localtime_r(&now, &local);
    strftime(buffer, size, "%H:%M:%S", &local);
}

static void sample_uptime(char *buffer, size_t size)
{
    FILE *fp = fopen("/proc/uptime", "re");
    double seconds = 0;
    long days;
    long hours;
    long minutes;
    long secs;

    if (fp != NULL) {
        if (fscanf(fp, "%lf", &seconds) != 1)
            seconds = 0;
        fclose(fp);
    }
    days = (long)seconds / 86400;
    hours = ((long)seconds % 86400) / 3600;
    minutes = ((long)seconds % 3600) / 60;
    secs = (long)seconds % 60;
    if (days > 0)
        snprintf(buffer, size, "up %ldd %02ld:%02ld:%02ld",
                 days, hours, minutes, secs);
    else
        snprintf(buffer, size, "up %02ld:%02ld:%02ld",
                 hours, minutes, secs);
}

static void sample_load(char *buffer, size_t size)
{
    FILE *fp = fopen("/proc/loadavg", "re");
    char one[16] = "?";
    char five[16] = "?";
    char fifteen[16] = "?";

    if (fp != NULL) {
        if (fscanf(fp, "%15s %15s %15s", one, five, fifteen) != 3)
            strcpy(one, "?");
        fclose(fp);
    }
    snprintf(buffer, size, "load %s %s %s", one, five, fifteen);
}

static void sample_mem(char *buffer, size_t size)
{
    FILE *fp = fopen("/proc/meminfo", "re");
    char key[32];
    char unit[16];
    unsigned long value;
    unsigned long total = 0;
    unsigned long available = 0;
    unsigned long used;

    if (fp != NULL) {
        while (fscanf(fp, "%31s %lu %15s", key, &value, unit) == 3) {
            if (strcmp(key, "MemTotal:") == 0)
                total = value;
            else if (strcmp(key, "MemAvailable:") == 0)
                available = value;
            if (total != 0 && available != 0)
                break;
        }
        fclose(fp);
    }
    used = total > available ? total - available : 0;
    snprintf(buffer, size, "mem %lu/%lu MiB", used / 1024, total / 1024);
}

static uint64_t read_uint_file(const char *path)
{
    FILE *fp = fopen(path, "re");
    uint64_t value = 0;

    if (fp != NULL) {
        if (fscanf(fp, "%llu", (unsigned long long *)&value) != 1)
            value = 0;
        fclose(fp);
    }
    return value;
}

static void sample_link(char *buffer, size_t size)
{
    char operstate[32] = "?";
    FILE *fp = fopen("/sys/class/net/usb0/operstate", "re");
    uint64_t rx = read_uint_file("/sys/class/net/usb0/statistics/rx_bytes");
    uint64_t tx = read_uint_file("/sys/class/net/usb0/statistics/tx_bytes");
    uint64_t rx_rate = rx >= prev_rx_bytes ? rx - prev_rx_bytes : 0;
    uint64_t tx_rate = tx >= prev_tx_bytes ? tx - prev_tx_bytes : 0;

    if (fp != NULL) {
        if (fscanf(fp, "%31s", operstate) != 1)
            strcpy(operstate, "?");
        fclose(fp);
    }
    snprintf(buffer, size, "usb0 %s  %lluK dn %lluK up", operstate,
             (unsigned long long)(rx_rate / 1024),
             (unsigned long long)(tx_rate / 1024));
    prev_rx_bytes = rx;
    prev_tx_bytes = tx;
}

static void status_timer_cb(lv_timer_t *timer)
{
    char text[64];
    (void)timer;

    sample_clock(text, sizeof(text));
    set_label(label_clock, text);
    sample_uptime(text, sizeof(text));
    set_label(label_uptime, text);
    sample_load(text, sizeof(text));
    set_label(label_load, text);
    sample_mem(text, sizeof(text));
    set_label(label_mem, text);
    sample_link(text, sizeof(text));
    set_label(label_link, text);

    heartbeat_on = !heartbeat_on;
    lv_obj_set_style_bg_color(heartbeat,
                              lv_color_hex(heartbeat_on ? 0x22d3ee : 0x134e4a),
                              0);
}

/* --- UI ------------------------------------------------------------------- */

static lv_obj_t *add_label(lv_obj_t *parent, const lv_font_t *font,
                           uint32_t color, lv_coord_t x, lv_coord_t y)
{
    lv_obj_t *label = lv_label_create(parent);

    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
    lv_obj_align(label, LV_ALIGN_TOP_LEFT, x, y);
    return label;
}

static void build_ui(void)
{
    lv_obj_t *screen = lv_screen_active();
    char hostname[32] = "claw";
    lv_obj_t *title;

    lv_obj_set_style_bg_color(screen, lv_color_hex(0x0b0f14), 0);

    gethostname(hostname, sizeof(hostname));
    hostname[sizeof(hostname) - 1] = '\0';

    title = add_label(screen, &lv_font_montserrat_32, 0x22d3ee, 12, 6);
    lv_label_set_text(title, hostname);

    /* Heartbeat dot, top right. */
    heartbeat = lv_obj_create(screen);
    lv_obj_set_size(heartbeat, 14, 14);
    lv_obj_align(heartbeat, LV_ALIGN_TOP_RIGHT, -12, 16);
    lv_obj_set_style_radius(heartbeat, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(heartbeat, lv_color_hex(0x134e4a), 0);
    lv_obj_set_style_border_width(heartbeat, 0, 0);

    label_clock = add_label(screen, &lv_font_montserrat_32, 0xe6edf3, 12, 48);
    lv_label_set_text(label_clock, "--:--:--");

    label_uptime = add_label(screen, &lv_font_montserrat_14, 0x9da7b3, 12, 96);
    label_load = add_label(screen, &lv_font_montserrat_14, 0x9da7b3, 12, 120);
    label_mem = add_label(screen, &lv_font_montserrat_14, 0x9da7b3, 12, 144);
    label_link = add_label(screen, &lv_font_montserrat_14, 0x9da7b3, 12, 168);

    {
        lv_obj_t *ip = add_label(screen, &lv_font_montserrat_20,
                                 0x64748b, 12, 206);
        lv_label_set_text(ip, "10.55.0.1");
    }
}

/* --- main ------------------------------------------------------------------ */

int main(int argc, char **argv)
{
    const char *spi_path = argc > 1 ? argv[1] : "/dev/spidev1.0";
    const char *gpiochip = argc > 2 ? argv[2] : "/dev/gpiochip0";
    uint32_t speed = argc > 3 ? (uint32_t)strtoul(argv[3], NULL, 10)
                              : UINT32_C(10000000);
    static uint8_t draw_buf_1[DRAW_BUF_SIZE];
    static uint8_t draw_buf_2[DRAW_BUF_SIZE];
    lv_display_t *display;

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    route_spi1_to_ethernet_pads();
    gpio_fd = request_control_lines(gpiochip);
    spi_fd = open_spi(spi_path, speed);
    lcd_init();
    lcd_log_identity();

    lv_init();
    lv_tick_set_cb(tick_get);
    display = lv_display_create(LCD_WIDTH, LCD_HEIGHT);
    lv_display_set_color_format(display, LV_COLOR_FORMAT_RGB565);
    lv_display_set_buffers(display, draw_buf_1, draw_buf_2,
                           sizeof(draw_buf_1), LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(display, flush_cb);

    build_ui();
    status_timer_cb(NULL);
    lv_timer_create(status_timer_cb, 1000, NULL);

    /* Backlight is active-low; first render is queued, light it up. */
    gpio_set(gpio_fd, GPIO_BACKLIGHT_INDEX, 0);
    printf("claw-lcd-status: LVGL dashboard on %s\n", spi_path);
    fflush(stdout);

    while (!stopping) {
        uint32_t wait_ms = lv_timer_handler();

        if (wait_ms > 100)
            wait_ms = 100;
        sleep_ms(wait_ms > 0 ? wait_ms : 1);
    }

    gpio_set(gpio_fd, GPIO_BACKLIGHT_INDEX, 1);
    close(spi_fd);
    close(gpio_fd);
    return EXIT_SUCCESS;
}
