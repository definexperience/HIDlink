#pragma once
// ---------------------------------------------------------------------------
// HIDlink BLE protocol  (keep in sync with app/lib/protocol.dart)
//
// GATT service   HIDLINK_SERVICE_UUID
//   input  char  HIDLINK_INPUT_UUID   write / write-without-response
//   status char  HIDLINK_STATUS_UUID  read / notify
//
// Every write to the input characteristic is ONE packet:
//   [type:u8][payload...]           multi-byte values are little endian
//
//   0x01 MOUSE      buttons:u8 dx:i16 dy:i16 wheel:i8 pan:i8
//                   buttons bit0=left bit1=right bit2=middle bit3=back bit4=fwd
//                   dx/dy are relative; large values are split by the dongle
//   0x02 KEYS       mods:u8 key1..key6:u8   raw HID keyboard state
//                   (send an all-zero packet to release)
//   0x03 TEXT       utf-8 bytes             typed using the selected layout;
//                   accents/€ etc. natively on US-Intl, otherwise via
//                   Alt-codes (Windows) or Ctrl+Shift+U (Linux)
//   0x04 CONSUMER   usage:u16               media key tap (volume, play, ...)
//   0x05 LAYOUT     id:u8                   select keyboard layout (saved)
//   0x06 RELEASE    –                       release all keys and buttons
//   0x07 OS         id:u8                   0 = Windows, 1 = Linux (saved);
//                   picks how non-ASCII characters are typed
//
// Status characteristic value (7 bytes):
//   [0] protocol version
//   [1] USB state: 0 = not connected to a PC, 1 = connected, 2 = connected
//       but the PC is in BIOS/boot mode (keyboard only)
//   [2] keyboard LEDs from the PC: bit0 NumLock bit1 CapsLock bit2 ScrollLock
//   [3] layout id
//   [4] number of paired phones
//   [5] flags: bit0 = pairing mode active, bit1 = typing in progress
//   [6] OS mode (0 Windows, 1 Linux)
// ---------------------------------------------------------------------------

#define HIDLINK_PROTOCOL_VERSION 2

#define HIDLINK_SERVICE_UUID "c0de0001-7b1e-4a5e-9d3f-4b1d0e5a1e00"
#define HIDLINK_INPUT_UUID   "c0de0002-7b1e-4a5e-9d3f-4b1d0e5a1e00"
#define HIDLINK_STATUS_UUID  "c0de0003-7b1e-4a5e-9d3f-4b1d0e5a1e00"

enum : uint8_t {
  PKT_MOUSE    = 0x01,
  PKT_KEYS     = 0x02,
  PKT_TEXT     = 0x03,
  PKT_CONSUMER = 0x04,
  PKT_LAYOUT   = 0x05,
  PKT_RELEASE  = 0x06,
  PKT_OSMODE   = 0x07,
};

// Layout ids. Must match the list in the app.
enum : uint8_t {
  LAYOUT_EN_US = 0,
  LAYOUT_US_INTL,   // US-International (dead keys) – common in NL
  LAYOUT_DE_DE,
  LAYOUT_FR_FR,
  LAYOUT_ES_ES,
  LAYOUT_IT_IT,
  LAYOUT_SV_SE,
  LAYOUT_DA_DK,
  LAYOUT_PT_PT,
  LAYOUT_PT_BR,
  LAYOUT_FR_CH,
  LAYOUT_HU_HU,
  LAYOUT_COUNT
};
