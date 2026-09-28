#pragma once
// ---------------------------------------------------------------------------
// HIDlink – user configuration
// Most options can also be set from platformio.ini with -D flags.
// ---------------------------------------------------------------------------

#define HIDLINK_FW_VERSION "1.1.0"

// BLE name shown on the phone: "<prefix>-XXXX" (XXXX = last 2 bytes of MAC)
#ifndef HIDLINK_NAME_PREFIX
#define HIDLINK_NAME_PREFIX "HIDlink"
#endif

// USB descriptor strings (what the PC shows in Device Manager)
#define USB_PRODUCT_NAME      "HIDlink Keyboard/Mouse"
#define USB_MANUFACTURER_NAME "HIDlink DIY"

// 1 = pair-once security: only phones that were paired while the dongle was
//     in pairing mode can control it (the bond is stored in flash).
// 0 = open: any phone running the app can connect and type.
#ifndef REQUIRE_BONDING
#define REQUIRE_BONDING 1
#endif

// How long pairing mode stays open after the button was held (ms)
#define PAIRING_WINDOW_MS 60000UL
// Hold the button this long, then release -> pairing mode
#define HOLD_PAIR_MS 3000UL
// Hold the button this long, then release -> forget all paired phones
#define HOLD_RESET_MS 10000UL
// A connected phone must finish pairing/encryption within this time (the user
// may need a moment to accept the pairing prompt on the phone), or it is dropped
#define AUTH_TIMEOUT_MS 30000UL

// Delay between typed characters of a text string (ms). Raise this if a slow
// target (BIOS, remote console, VM) drops characters.
#ifndef TYPE_DELAY_MS
#define TYPE_DELAY_MS 4
#endif

// Hardware options
#ifndef HAS_LCD
#define HAS_LCD 1
#endif
#ifndef HAS_APA102
#define HAS_APA102 1
#endif

// ---------------------------------------------------------------------------
// T-Dongle-S3 pins (from the LilyGO repository)
// ---------------------------------------------------------------------------
#define PIN_BUTTON   0   // BOOT button (active low)

#define PIN_LCD_MOSI 3
#define PIN_LCD_CLK  5
#define PIN_LCD_CS   4
#define PIN_LCD_DC   2
#define PIN_LCD_RST  1
#define PIN_LCD_BL   38  // backlight, active LOW

#define PIN_LED_DI   40  // APA102 RGB LED data
#define PIN_LED_CI   39  // APA102 RGB LED clock

#ifdef HIDLINK_DEBUG
#define DBG(...) Serial.printf(__VA_ARGS__)
#else
#define DBG(...) do {} while (0)
#endif
