# Third-party notices

HIDlink's own code is MIT licensed (see [LICENSE](LICENSE)). It uses the
following third-party software. All of these licences allow commercial use.

## Included in this repository

| Files | Project | Licence |
|---|---|---|
| `firmware/src/esp_lcd_st7735.c`, `firmware/src/esp_lcd_st7735.h` | [LilyGO T-Dongle-S3](https://github.com/Xinyuan-LilyGO/T-Dongle-S3), © 2022 Xinyuan-LilyGO | MIT |

The board definition `firmware/boards/t-dongle-s3.json` is based on the one in
the same LilyGO repository.

## Downloaded at build time (not included)

### Firmware

| Project | Licence |
|---|---|
| [Arduino-ESP32 core](https://github.com/espressif/arduino-esp32) | LGPL-2.1 |
| [ESP-IDF](https://github.com/espressif/esp-idf) (incl. TinyUSB) | Apache-2.0 (TinyUSB: MIT) |
| [pioarduino platform-espressif32](https://github.com/pioarduino/platform-espressif32) | Apache-2.0 |
| [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) | Apache-2.0 |
| [Adafruit GFX Library](https://github.com/adafruit/Adafruit-GFX-Library) | BSD |

The prebuilt firmware images published as releases contain these libraries.
The Arduino-ESP32 core is LGPL-2.1; its complete source code is available at
the link above.

### App

| Project | Licence |
|---|---|
| [Flutter](https://github.com/flutter/flutter) | BSD-3-Clause |
| [universal_ble](https://github.com/Navideck/universal_ble) | BSD-3-Clause |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | BSD-3-Clause |

Flutter can show the full licence texts of everything bundled in the app via
`showLicensePage()`.
