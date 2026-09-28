// LCD status screen (ST7735, 160x80) + APA102 status LED
#include "config.h"
#include "ui.h"

#if HAS_LCD
#include <Adafruit_GFX.h>
#include "driver/spi_master.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_st7735.h"

static constexpr int W = 160, H = 80;

static esp_lcd_panel_handle_t panel = nullptr;
static GFXcanvas16 *canvas = nullptr;
static uint16_t *dmaBuf = nullptr;
static SemaphoreHandle_t flushDone = nullptr;

static bool IRAM_ATTR onFlushDone(esp_lcd_panel_io_handle_t, esp_lcd_panel_io_event_data_t *, void *) {
  BaseType_t woken = pdFALSE;
  xSemaphoreGiveFromISR(flushDone, &woken);
  return woken == pdTRUE;
}

// RGB888 -> RGB565
static constexpr uint16_t rgb(uint8_t r, uint8_t g, uint8_t b) {
  return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}
static constexpr uint16_t C_BG = rgb(0, 0, 0);
static constexpr uint16_t C_BAR = rgb(30, 41, 59);
static constexpr uint16_t C_TXT = rgb(235, 235, 235);
static constexpr uint16_t C_DIM = rgb(120, 130, 140);
static constexpr uint16_t C_OK = rgb(34, 197, 94);
static constexpr uint16_t C_WARN = rgb(245, 180, 20);
static constexpr uint16_t C_OFF = rgb(90, 90, 90);
static constexpr uint16_t C_BLUE = rgb(60, 140, 255);
static constexpr uint16_t C_RED = rgb(239, 68, 68);

void displayBacklight(bool on) { digitalWrite(PIN_LCD_BL, on ? LOW : HIGH); }

void displayBegin() {
  pinMode(PIN_LCD_BL, OUTPUT);
  displayBacklight(false);

  flushDone = xSemaphoreCreateBinary();
  xSemaphoreGive(flushDone);

  spi_bus_config_t bus = {};
  bus.mosi_io_num = PIN_LCD_MOSI;
  bus.miso_io_num = -1;
  bus.sclk_io_num = PIN_LCD_CLK;
  bus.quadwp_io_num = -1;
  bus.quadhd_io_num = -1;
  bus.max_transfer_sz = W * H * 2;
  ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_CH_AUTO));

  esp_lcd_panel_io_handle_t io = nullptr;
  esp_lcd_panel_io_spi_config_t ioCfg = {};
  ioCfg.cs_gpio_num = PIN_LCD_CS;
  ioCfg.dc_gpio_num = PIN_LCD_DC;
  ioCfg.spi_mode = 0;
  ioCfg.pclk_hz = 40 * 1000 * 1000;
  ioCfg.trans_queue_depth = 10;
  ioCfg.on_color_trans_done = onFlushDone;
  ioCfg.lcd_cmd_bits = 8;
  ioCfg.lcd_param_bits = 8;
  ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)SPI2_HOST, &ioCfg, &io));

  esp_lcd_panel_dev_config_t pCfg = {};
  pCfg.reset_gpio_num = PIN_LCD_RST;
  pCfg.rgb_ele_order = LCD_RGB_ELEMENT_ORDER_BGR;
  pCfg.data_endian = LCD_RGB_DATA_ENDIAN_LITTLE;
  pCfg.bits_per_pixel = 16;
  ESP_ERROR_CHECK(esp_lcd_new_panel_st7735(io, &pCfg, &panel));
  ESP_ERROR_CHECK(esp_lcd_panel_reset(panel));
  ESP_ERROR_CHECK(esp_lcd_panel_init(panel));
  ESP_ERROR_CHECK(esp_lcd_panel_invert_color(panel, true));
  // Landscape, same settings as the LilyGO factory firmware
  esp_lcd_panel_set_gap(panel, 1, 26);
  esp_lcd_panel_swap_xy(panel, true);
  ESP_ERROR_CHECK(esp_lcd_panel_mirror(panel, false, true));
  ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(panel, true));

  canvas = new GFXcanvas16(W, H);
  dmaBuf = (uint16_t *)heap_caps_malloc(W * H * 2, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
  canvas->fillScreen(C_BG);
  displayBacklight(true);
}

static void flush() {
  if (!panel || !canvas || !dmaBuf) return;
  // wait until the previous frame has left the DMA buffer
  xSemaphoreTake(flushDone, pdMS_TO_TICKS(200));
  const uint16_t *src = canvas->getBuffer();
  for (int i = 0; i < W * H; i++) dmaBuf[i] = (src[i] >> 8) | (src[i] << 8);  // panel wants big endian
  esp_lcd_panel_draw_bitmap(panel, 0, 0, W, H, dmaBuf);
}

static void text(int x, int y, const char *s, uint16_t color, uint8_t size = 1) {
  canvas->setTextSize(size);
  canvas->setTextColor(color);
  canvas->setCursor(x, y);
  canvas->print(s);
}

static void textCentered(int y, const char *s, uint16_t color, uint8_t size = 1) {
  int w = strlen(s) * 6 * size;
  text((W - w) / 2, y, s, color, size);
}

static void statusRow(int y, const char *label, const char *value, uint16_t dot) {
  canvas->fillCircle(6, y + 3, 3, dot);
  text(14, y, label, C_DIM);
  text(56, y, value, C_TXT);
}

static void drawHold(const UiState &s) {
  canvas->fillRect(0, 0, W, 14, C_BAR);
  text(4, 3, "Button held", C_TXT);
  char buf[16];
  snprintf(buf, sizeof buf, "%lus", (unsigned long)(s.holdMs / 1000));
  text(W - 6 * strlen(buf) - 4, 3, buf, C_DIM);

  // progress bar 0..HOLD_RESET_MS with a tick at HOLD_PAIR_MS
  const int bx = 8, by = 24, bw = W - 16, bh = 10;
  uint32_t t = min<uint32_t>(s.holdMs, HOLD_RESET_MS);
  int fill = (int)((uint64_t)bw * t / HOLD_RESET_MS);
  uint16_t col = s.holdMs >= HOLD_RESET_MS ? C_RED : (s.holdMs >= HOLD_PAIR_MS ? C_BLUE : C_DIM);
  canvas->drawRect(bx, by, bw, bh, C_DIM);
  canvas->fillRect(bx + 1, by + 1, max(0, fill - 2), bh - 2, col);
  int tick = bx + (int)((uint64_t)bw * HOLD_PAIR_MS / HOLD_RESET_MS);
  canvas->drawFastVLine(tick, by - 3, bh + 6, C_TXT);

  if (s.holdMs >= HOLD_RESET_MS) {
    textCentered(44, "Release:", C_TXT);
    textCentered(58, "FORGET ALL PHONES", C_RED);
  } else if (s.holdMs >= HOLD_PAIR_MS) {
    textCentered(44, "Release: PAIR PHONE", C_BLUE);
    textCentered(62, "hold to 10s = reset", C_DIM);
  } else {
    textCentered(44, "3s = pair new phone", C_DIM);
    textCentered(58, "10s = forget all", C_DIM);
  }
}

static void drawInfo(const UiState &s) {
  canvas->fillRect(0, 0, W, 14, C_BAR);
  text(4, 3, s.name, C_TXT);
  char buf[32];
  snprintf(buf, sizeof buf, "FW %s", HIDLINK_FW_VERSION);
  text(4, 20, buf, C_TXT);
  snprintf(buf, sizeof buf, "Paired phones: %u", s.bonds);
  text(4, 32, buf, C_TXT);
  text(4, 44, s.open ? "Security: OPEN" : "Security: pair-once", s.open ? C_WARN : C_TXT);
  text(4, 58, "Hold 3s: pair", C_DIM);
  text(4, 68, "Hold 10s: forget all", C_DIM);
}

static void drawMain(const UiState &s) {
  canvas->fillRect(0, 0, W, 14, C_BAR);
  text(4, 3, s.name, C_TXT);

  const char *usb = s.usb == 0 ? "no PC" : (s.usb == 2 ? "BIOS mode" : "connected");
  statusRow(19, "PC", usb, s.usb ? C_OK : C_OFF);

  const char *ble;
  uint16_t bleDot;
  switch (s.ble) {
    case BleState::Connected: ble = "connected"; bleDot = C_OK; break;
    case BleState::Securing:  ble = "securing.."; bleDot = C_WARN; break;
    default:                  ble = "waiting"; bleDot = C_OFF; break;
  }
  statusRow(31, "Phone", ble, bleDot);

  // message area
  char buf[32];
  if (s.pairingSecsLeft) {
    canvas->fillRoundRect(2, 44, W - 4, 22, 4, C_BLUE);
    snprintf(buf, sizeof buf, "PAIRING %lus", (unsigned long)s.pairingSecsLeft);
    canvas->setTextColor(C_TXT);
    textCentered(48, buf, C_TXT, 2);
  } else if (s.msg[0]) {
    textCentered(50, s.msg, C_WARN);
  } else if (s.typing) {
    textCentered(50, "typing...", C_OK);
  } else if (s.open) {
    textCentered(50, "security OFF", C_WARN);
  }

  // footer
  snprintf(buf, sizeof buf, "Kbd %s", s.layout);
  text(4, 70, buf, C_DIM);
  if (s.caps) {
    canvas->fillRoundRect(W - 32, 68, 30, 11, 2, C_WARN);
    text(W - 29, 70, "CAPS", C_BG);
  }
}

void displayRender(const UiState &s) {
  if (!canvas) return;
  canvas->fillScreen(C_BG);
  if (s.holdMs >= 700) drawHold(s);
  else if (s.infoPage) drawInfo(s);
  else drawMain(s);
  flush();
}

#else  // no LCD
void displayBegin() {}
void displayRender(const UiState &) {}
void displayBacklight(bool) {}
#endif

// ---------------------------------------------------------------------------
// APA102 single RGB LED, bit-banged (only a few bytes, no library needed)
// ---------------------------------------------------------------------------
#if HAS_APA102
static void apaByte(uint8_t b) {
  for (int i = 7; i >= 0; i--) {
    digitalWrite(PIN_LED_DI, (b >> i) & 1);
    digitalWrite(PIN_LED_CI, HIGH);
    digitalWrite(PIN_LED_CI, LOW);
  }
}
void ledBegin() {
  pinMode(PIN_LED_DI, OUTPUT);
  pinMode(PIN_LED_CI, OUTPUT);
  digitalWrite(PIN_LED_CI, LOW);
  ledSet(0, 0, 0);
}
void ledSet(uint8_t r, uint8_t g, uint8_t b) {
  static int32_t last = -1;
  int32_t v = (r << 16) | (g << 8) | b;
  if (v == last) return;
  last = v;
  for (int i = 0; i < 4; i++) apaByte(0x00);  // start frame
  apaByte(0xE0 | 4);                           // low global brightness (0..31)
  apaByte(b);
  apaByte(g);
  apaByte(r);
  for (int i = 0; i < 4; i++) apaByte(0xFF);  // end frame
}
#else
void ledBegin() {}
void ledSet(uint8_t, uint8_t, uint8_t) {}
#endif
