#pragma once
#include <Arduino.h>

enum class BleState : uint8_t { Advertising, Securing, Connected };

struct UiState {
  const char *name = "";
  const char *layout = "";
  uint8_t usb = 0;             // 0 none, 1 mounted, 2 mounted in boot mode
  BleState ble = BleState::Advertising;
  uint32_t pairingSecsLeft = 0; // 0 = not in pairing mode
  uint8_t bonds = 0;
  bool caps = false;
  bool typing = false;
  uint32_t holdMs = 0;          // button held for this long (0 = not held)
  bool infoPage = false;
  bool open = false;            // security disabled
  char msg[24] = "";            // short transient message
  bool operator==(const UiState &o) const {
    return usb == o.usb && ble == o.ble && pairingSecsLeft == o.pairingSecsLeft && bonds == o.bonds &&
           caps == o.caps && typing == o.typing && holdMs / 100 == o.holdMs / 100 && infoPage == o.infoPage &&
           layout == o.layout && strcmp(msg, o.msg) == 0;
  }
};

// LCD
void displayBegin();
void displayRender(const UiState &s);
void displayBacklight(bool on);

// APA102 RGB LED
void ledBegin();
void ledSet(uint8_t r, uint8_t g, uint8_t b);
