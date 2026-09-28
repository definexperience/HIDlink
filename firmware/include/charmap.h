#pragma once
// ---------------------------------------------------------------------------
// Non-ASCII characters
//
// 1. US-International layout: typed the native way, with dead keys
//    (' " ` ~ ^ followed by a letter) or AltGr combinations. Only entries
//    that are the same on Windows "US-International" and Linux
//    "English (US, intl., with dead keys)" are listed here.
// 2. Everything else falls back to an OS input method:
//    Windows: Alt + numpad code (Windows-1252 code page)
//    Linux:   Ctrl+Shift+U <hex> Space (GTK / IBus apps)
// ---------------------------------------------------------------------------
#include <stdint.h>

enum : uint8_t { OS_WINDOWS = 0, OS_LINUX = 1, OS_COUNT };

// HID modifier bits
#define HM_SHIFT 0x02
#define HM_ALTGR 0x40

struct IntlChar {
  uint16_t cp;   // Unicode code point
  char dead;     // dead key to press first (0 = AltGr combination instead)
  char base;     // letter typed after the dead key
  uint8_t key;   // HID usage for an AltGr combination
  uint8_t mods;  // modifiers for an AltGr combination
};

static const IntlChar US_INTL_CHARS[] = {
  // ' acute
  {0xE1, '\'', 'a'}, {0xE9, '\'', 'e'}, {0xED, '\'', 'i'}, {0xF3, '\'', 'o'}, {0xFA, '\'', 'u'}, {0xFD, '\'', 'y'},
  {0xC1, '\'', 'A'}, {0xC9, '\'', 'E'}, {0xCD, '\'', 'I'}, {0xD3, '\'', 'O'}, {0xDA, '\'', 'U'}, {0xDD, '\'', 'Y'},
  // " diaeresis
  {0xE4, '"', 'a'}, {0xEB, '"', 'e'}, {0xEF, '"', 'i'}, {0xF6, '"', 'o'}, {0xFC, '"', 'u'}, {0xFF, '"', 'y'},
  {0xC4, '"', 'A'}, {0xCB, '"', 'E'}, {0xCF, '"', 'I'}, {0xD6, '"', 'O'}, {0xDC, '"', 'U'},
  // ` grave
  {0xE0, '`', 'a'}, {0xE8, '`', 'e'}, {0xEC, '`', 'i'}, {0xF2, '`', 'o'}, {0xF9, '`', 'u'},
  {0xC0, '`', 'A'}, {0xC8, '`', 'E'}, {0xCC, '`', 'I'}, {0xD2, '`', 'O'}, {0xD9, '`', 'U'},
  // ~ tilde
  {0xE3, '~', 'a'}, {0xF5, '~', 'o'}, {0xF1, '~', 'n'}, {0xC3, '~', 'A'}, {0xD5, '~', 'O'}, {0xD1, '~', 'N'},
  // ^ circumflex
  {0xE2, '^', 'a'}, {0xEA, '^', 'e'}, {0xEE, '^', 'i'}, {0xF4, '^', 'o'}, {0xFB, '^', 'u'},
  {0xC2, '^', 'A'}, {0xCA, '^', 'E'}, {0xCE, '^', 'I'}, {0xD4, '^', 'O'}, {0xDB, '^', 'U'},
  // AltGr combinations
  {0x20AC, 0, 0, 0x22, HM_ALTGR},            // € AltGr+5
  {0x00DF, 0, 0, 0x16, HM_ALTGR},            // ß AltGr+s
  {0x00A7, 0, 0, 0x16, HM_ALTGR | HM_SHIFT}, // § AltGr+Shift+s
  {0x00E7, 0, 0, 0x36, HM_ALTGR},            // ç AltGr+,
  {0x00C7, 0, 0, 0x36, HM_ALTGR | HM_SHIFT}, // Ç
  {0x00A3, 0, 0, 0x21, HM_ALTGR | HM_SHIFT}, // £ AltGr+Shift+4
  {0x00A9, 0, 0, 0x06, HM_ALTGR},            // © AltGr+c
  {0x00AE, 0, 0, 0x15, HM_ALTGR},            // ® AltGr+r
  {0x00B5, 0, 0, 0x10, HM_ALTGR},            // µ AltGr+m
  {0x00BF, 0, 0, 0x38, HM_ALTGR},            // ¿ AltGr+/
  {0x00A1, 0, 0, 0x1E, HM_ALTGR},            // ¡ AltGr+1
  {0x00B2, 0, 0, 0x1F, HM_ALTGR},            // ² AltGr+2
  {0x00B3, 0, 0, 0x20, HM_ALTGR},            // ³ AltGr+3
  {0x00B6, 0, 0, 0x33, HM_ALTGR},            // ¶ AltGr+;
  {0x00B0, 0, 0, 0x33, HM_ALTGR | HM_SHIFT}, // ° AltGr+Shift+;
  {0x00D7, 0, 0, 0x2E, HM_ALTGR},            // × AltGr+=
  {0x00AB, 0, 0, 0x2F, HM_ALTGR},            // « AltGr+[
  {0x00BB, 0, 0, 0x30, HM_ALTGR},            // » AltGr+]
  {0x00E6, 0, 0, 0x1D, HM_ALTGR},            // æ AltGr+z
  {0x00C6, 0, 0, 0x1D, HM_ALTGR | HM_SHIFT}, // Æ
  {0x00E5, 0, 0, 0x1A, HM_ALTGR},            // å AltGr+w
  {0x00C5, 0, 0, 0x1A, HM_ALTGR | HM_SHIFT}, // Å
  {0x00F8, 0, 0, 0x0F, HM_ALTGR},            // ø AltGr+l
  {0x00D8, 0, 0, 0x0F, HM_ALTGR | HM_SHIFT}, // Ø
};

static const IntlChar *findUsIntl(uint32_t cp) {
  for (const IntlChar &c : US_INTL_CHARS)
    if (c.cp == cp) return &c;
  return nullptr;
}

// Unicode -> Windows-1252 byte (for Alt+0nnn codes). 0 = not available.
static uint8_t toCp1252(uint32_t cp) {
  if (cp >= 0xA0 && cp <= 0xFF) return (uint8_t)cp;
  static const uint16_t hi[32] = {
    0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0,
    0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178,
  };
  for (int i = 0; i < 32; i++)
    if (hi[i] && hi[i] == cp) return 0x80 + i;
  return 0;
}
