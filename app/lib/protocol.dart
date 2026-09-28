// HIDlink BLE protocol – keep in sync with firmware/include/protocol.h
import 'dart:typed_data';

class Hid {
  static const serviceUuid = 'c0de0001-7b1e-4a5e-9d3f-4b1d0e5a1e00';
  static const inputUuid = 'c0de0002-7b1e-4a5e-9d3f-4b1d0e5a1e00';
  static const statusUuid = 'c0de0003-7b1e-4a5e-9d3f-4b1d0e5a1e00';

  static const pktMouse = 0x01;
  static const pktKeys = 0x02;
  static const pktText = 0x03;
  static const pktConsumer = 0x04;
  static const pktLayout = 0x05;
  static const pktRelease = 0x06;
  static const pktOsMode = 0x07;

  static Uint8List mouse(int buttons, int dx, int dy, int wheel, int pan) {
    final b = ByteData(8);
    b.setUint8(0, pktMouse);
    b.setUint8(1, buttons & 0x1F);
    b.setInt16(2, dx.clamp(-32768, 32767).toInt(), Endian.little);
    b.setInt16(4, dy.clamp(-32768, 32767).toInt(), Endian.little);
    b.setInt8(6, wheel.clamp(-127, 127).toInt());
    b.setInt8(7, pan.clamp(-127, 127).toInt());
    return b.buffer.asUint8List();
  }

  static Uint8List keys(int mods, List<int> keys) {
    final out = Uint8List(8);
    out[0] = pktKeys;
    out[1] = mods & 0xFF;
    for (var i = 0; i < keys.length && i < 6; i++) {
      out[2 + i] = keys[i];
    }
    return out;
  }

  static Uint8List text(List<int> utf8Bytes) => Uint8List.fromList([pktText, ...utf8Bytes]);

  static Uint8List consumer(int usage) => Uint8List.fromList([pktConsumer, usage & 0xFF, (usage >> 8) & 0xFF]);

  static Uint8List layout(int id) => Uint8List.fromList([pktLayout, id]);

  static Uint8List release() => Uint8List.fromList([pktRelease]);

  static Uint8List osMode(int id) => Uint8List.fromList([pktOsMode, id]);
}

/// Parsed value of the status characteristic.
class DongleStatus {
  final int protocol;
  final int usb; // 0 no PC, 1 connected, 2 BIOS/boot mode
  final int leds;
  final int layout;
  final int bonds;
  final bool pairing;
  final int osMode; // 0 Windows, 1 Linux

  const DongleStatus({
    this.protocol = 0,
    this.usb = 0,
    this.leds = 0,
    this.layout = 0,
    this.bonds = 0,
    this.pairing = false,
    this.osMode = 0,
  });

  factory DongleStatus.parse(List<int> v) {
    if (v.length < 6) return const DongleStatus();
    return DongleStatus(
      protocol: v[0],
      usb: v[1],
      leds: v[2],
      layout: v[3],
      bonds: v[4],
      pairing: (v[5] & 1) != 0,
      osMode: v.length > 6 ? v[6] : 0,
    );
  }

  bool get capsLock => (leds & 0x02) != 0;
  bool get numLock => (leds & 0x01) != 0;
  bool get pcConnected => usb != 0;
  bool get biosMode => usb == 2;
}

/// Keyboard layouts supported by the dongle (index = layout id).
/// Target operating system: decides how accents, € etc. are typed when the
/// keyboard layout can't produce them directly.
class OsModes {
  static const windows = 0;
  static const linux = 1;
  static const names = ['Windows', 'Linux'];
}

/// Which characters the dongle can type (mirrors the firmware logic).
class Typable {
  static const _cp1252Extra = {
    0x20AC, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x017D,
    0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x017E, 0x0178,
  };

  /// [bios]: in BIOS/boot mode only plain ASCII works.
  static bool check(int rune, {required int osMode, required bool bios}) {
    if (rune == 0x0A || rune == 0x09 || rune == 0x0D) return true;
    if (rune < 0x20 || rune == 0x7F) return false;
    if (rune < 0x80) return true;
    if (bios) return false;
    if (osMode == OsModes.linux) return true; // Ctrl+Shift+U handles any code point
    return rune <= 0xFF || _cp1252Extra.contains(rune); // Windows Alt codes
  }
}

class Layouts {
  static const names = <String>[
    'US (QWERTY)',
    'US-International',
    'German (QWERTZ)',
    'French (AZERTY)',
    'Spanish',
    'Italian',
    'Swedish',
    'Danish',
    'Portuguese',
    'Brazilian',
    'Swiss French',
    'Hungarian',
  ];
  static const usIntl = 1;
  static const de = 2;
  static const fr = 3;
  static const chFr = 10;
  static const hu = 11;
}

/// USB HID modifier bits
class Mod {
  static const ctrl = 0x01;
  static const shift = 0x02;
  static const alt = 0x04;
  static const gui = 0x08; // Windows / Command key
  static const rAlt = 0x40; // AltGr
}

/// USB HID keyboard usages (page 0x07)
class HidKey {
  static const enter = 0x28;
  static const esc = 0x29;
  static const backspace = 0x2A;
  static const tab = 0x2B;
  static const space = 0x2C;
  static const capsLock = 0x39;
  static const f1 = 0x3A; // f1..f12 = 0x3A..0x45
  static const printScreen = 0x46;
  static const scrollLock = 0x47;
  static const pause = 0x48;
  static const insert = 0x49;
  static const home = 0x4A;
  static const pageUp = 0x4B;
  static const delete = 0x4C;
  static const end = 0x4D;
  static const pageDown = 0x4E;
  static const right = 0x4F;
  static const left = 0x50;
  static const down = 0x51;
  static const up = 0x52;
  static const numLock = 0x53;
  static const menu = 0x65;

  static int f(int n) => n <= 12 ? f1 + n - 1 : 0x68 + n - 13;

  /// Physical key for a letter or digit, taking QWERTZ/AZERTY into account.
  /// Used for shortcuts like Ctrl+C, so they hit the right key on the PC.
  static int? forChar(String ch, int layout) {
    var c = ch.toLowerCase();
    if (c.length != 1) return null;
    final qwertz = layout == Layouts.de || layout == Layouts.chFr || layout == Layouts.hu;
    final azerty = layout == Layouts.fr;
    if (qwertz) {
      if (c == 'y') {
        c = 'z';
      } else if (c == 'z') {
        c = 'y';
      }
    }
    if (azerty) {
      const swap = {'a': 'q', 'q': 'a', 'z': 'w', 'w': 'z'};
      if (c == 'm') return 0x33; // M sits where ';' is on US
      c = swap[c] ?? c;
    }
    final code = c.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7A) return 0x04 + code - 0x61; // a..z
    if (code >= 0x31 && code <= 0x39) return 0x1E + code - 0x31; // 1..9
    if (c == '0') return 0x27;
    if (c == ' ') return space;
    return null;
  }
}

/// Consumer-page usages (media keys)
class Media {
  static const volUp = 0xE9;
  static const volDown = 0xEA;
  static const mute = 0xE2;
  static const playPause = 0xCD;
  static const next = 0xB5;
  static const prev = 0xB6;
  static const stop = 0xB7;
}
