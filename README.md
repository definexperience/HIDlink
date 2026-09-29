# HIDlink: phone → BLE → USB keyboard & mouse

A DIY alternative to EmulStick. You plug a **LilyGO T‑Dongle‑S3** into any PC.
The PC sees a normal USB keyboard and mouse, with no drivers, and the keyboard also works in BIOS/UEFI.
You control it from a phone app over Bluetooth LE, so your phone stays on its normal Wi‑Fi.
Developed as a tool for service engineers to troubleshoot computers without a mouse and or keyboard.

```
 ┌──────────┐   Bluetooth LE    ┌────────────────┐   USB HID    ┌──────┐
 │ phone app│ ────────────────▶ │ T-Dongle-S3    │ ───────────▶ │  PC  │
 │ (Flutter)│  pair once, then  │ ESP32-S3       │  keyboard +  │      │
 └──────────┘  auto-reconnect   │ LCD shows state│  mouse+media │      │
                                └────────────────┘              └──────┘
```

```
hidlink/
├── firmware/   PlatformIO project for the dongle (Arduino-ESP32 3.3 + NimBLE)
├── app/        Flutter app (Android + iOS)
└── prebuilt/   place for ready-to-flash firmware images (published as GitHub Releases)
```

Get the code:

```bash
git clone https://github.com/<your-account>/hidlink.git
```

---

## 1. Flash the dongle

### Option A: prebuilt image, from the browser (easiest)

Download the `.factory.bin` file for your board from the repository's **Releases** page. The images aren't stored in the repository itself.

1. Put the dongle in **download mode**: hold the button on the dongle while you plug it into the PC, then release the button.
2. Open <https://espressif.github.io/esptool-js/> in Chrome or Edge.
3. Set the baud rate to 921600, click **Connect**, and choose the "USB JTAG/serial" port.
4. Under *Flash Address*, enter `0x0`. As the file, choose the downloaded `hidlink-t-dongle-s3-v1.1.0.factory.bin`, then click **Program**.
5. Unplug the dongle and plug it back in. The screen shows `HIDlink-XXXX` and **PAIRING**.

| Image | Use for |
|---|---|
| `hidlink-t-dongle-s3-…` | **Normal use.** Keyboard + mouse, with pair‑once security. |
| `hidlink-t-dongle-s3-nolcd-…` | Dongle variants without a screen (e.g. T‑Dongle‑S3‑Dual). |
| `hidlink-t-dongle-s3-debug-…` | Development. Adds a USB serial port with log output. |

### Option B: build from source (PlatformIO)

Install VS Code with the PlatformIO extension, or use the CLI (`pip install platformio`).

```bash
cd firmware
pio run -e t-dongle-s3            # build
pio run -e t-dongle-s3 -t upload  # flash (dongle must be in download mode, see above)
```

The first build downloads the pioarduino platform, which bundles Arduino‑ESP32 core 3.3.x. That takes a few minutes.

> **Re-flashing:** the normal firmware is a pure keyboard/mouse, so it has no serial port.
> Always enter download mode first: hold the button while plugging in.
> The `-debug` build keeps a serial port, so you can upload to it directly.

---

## 2. Using the dongle

**Screen**

| Line | Meaning |
|---|---|
| `PC connected` / `no PC` / `BIOS mode` | USB state. In BIOS mode only the keyboard works, because BIOS doesn't support a mouse from this dongle. |
| `Phone connected` / `securing..` / `waiting` | Bluetooth state |
| `PAIRING 57s` | The dongle accepts a new phone for the next 57 seconds |
| `Kbd US-Intl` + `CAPS` | The selected PC keyboard layout, and the Caps Lock state reported by the PC |

**LED:** blinking blue = pairing mode, green = phone connected (bright while typing), yellow = phone is setting up encryption.

**Button**

| Action | Result |
|---|---|
| Short press | Show the info page (paired phones, firmware version). A short press also cancels pairing mode. |
| Hold 3 s, then release | **Pairing mode** for 60 s, to add another phone |
| Hold 10 s, then release | **Forget all phones**, then pairing mode |

The screen shows a progress bar while you hold the button, so you can see which action you'll get when you let go.

### Pair once

* **First use:** a fresh dongle has no paired phone, so it starts in pairing mode automatically. Open the app, tap the dongle, and accept the pairing prompt. Done.
* **From then on:** plug in the dongle and open the app. It reconnects on its own, with no code and no prompt. The bond is stored in the dongle's flash and survives power cycles. Up to 3 phones can be paired.
* **Another phone** only gets in while the dongle is in pairing mode, which you start by holding the button for 3 s. Outside pairing mode, unknown phones are refused.
* **After "forget all"** (10 s hold), also remove `HIDlink-XXXX` from the phone's Bluetooth settings, or use the app's **Settings → Forget this dongle**. Otherwise the phone keeps trying the old key.

---

## 3. Build the app

The app folder contains only the Dart source. `flutter create` generates the Android and iOS project folders, and a small script then adds the Bluetooth permissions.

1. Install Flutter 3.27 or newer (<https://docs.flutter.dev/get-started/install>) and run `flutter doctor`.
2. In the `app` folder, run:

```bash
cd app
flutter create --org nl.yourcompany --project-name hidlink --platforms=android,ios .
dart run tool/setup.dart        # adds Bluetooth permissions + app name
flutter pub get
```

### Android

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

Copy the APK to the phone and install it. You need to allow "install unknown apps" once.
You can also connect the phone with USB debugging enabled and run `flutter run --release`.
No Play Store account is needed.

### iOS (optional)

You need a Mac with Xcode. Open `app/ios/Runner.xcworkspace`, choose your Apple ID under *Signing & Capabilities*, and run the app on your iPhone.

* With a free Apple ID, the app expires after 7 days and must be reinstalled.
* With a paid developer account (€99/yr), you can use TestFlight or ad‑hoc distribution.
* If `pod install` complains about the iOS version, set `platform :ios, '13.1'` in `ios/Podfile`. The setup script does this if the file exists.

The code is identical for both platforms. iOS pairs automatically when the app first reads from the dongle.

---

## 4. Using the app

* **Trackpad:** move one finger to move the pointer. Tap to left‑click, tap with two fingers to right‑click, and tap with three fingers to middle‑click. Move two fingers to scroll, or use the strip on the right. To drag, tap and then touch again and move.
* **Left / Mid / Right** are real buttons you can hold. For example, hold *Left* with your thumb and drag on the pad.
* **Ctrl / Shift / Alt / Win / AltGr:** a tap applies the modifier to the next key only. A long‑press locks it (🔒).
* **Key tabs**
  * Keys: Esc, Tab, Enter, Del, **Pause/Break** and similar
  * F1–F12
  * Arrows: arrows, Home, End, PgUp, PgDn
  * Shortcuts: Ctrl+Alt+Del, Task Manager, **Ctrl+Break**, Alt+Tab, Win+R, Ctrl+C/V and more
  * Media: volume and playback
  * Keys are held for as long as your finger is on them, so the PC's own key repeat works.
* **Text bar**
  * *Send mode* (default): type or paste text, then tap **Type** (or ⏎ to add Enter). This is good for passwords, commands, and long text.
  * *Live mode* (keyboard icon): every key you press on the phone goes straight to the PC. The text field is hidden and the phone keyboard stays open; tap the *Tap here to type live* bar if the keyboard was closed.
  * **Paste** (clipboard button on the right): types whatever is on the phone's clipboard, in one tap. Copy a password on the phone, tap Paste, done. The text is never shown on screen, and a trailing line break is dropped, so it doesn't press Enter by accident. Android 12+ shows a short "pasted from clipboard" notice. iOS may ask "Allow Paste": set it to *Allow* in the iPhone Settings for HIDlink.
* **Layout chip** (top right): set this to the PC's keyboard layout, e.g. *US‑International*, which is common in NL. Typed text then comes out correctly. The setting is saved on the dongle, and a fresh dongle starts on US‑International.
* **⋮ menu:** Settings (pointer speed, acceleration, natural scrolling, tap‑to‑click, PC operating system), *Release all keys*, and Disconnect.

### Special characters (é, ë, €, £, °, …)

All normal keyboard symbols (`! @ # $ % ^ & * ( ) - _ = + [ ] { } \ | ; : ' " , . / < > ? ~`) always work. For characters beyond that:

1. **On the US‑International layout (default)**, the dongle types them the way a person would, which works on Windows and Linux:
   * with dead keys: á é í ó ú ý, ä ë ï ö ü ÿ, à è ì ò ù, â ê î ô û, ã õ ñ (and capitals)
   * with AltGr: € ß § ç Ç £ © ® µ ¿ ¡ ² ³ ¶ ° × « » æ Æ å Å ø Ø
2. **Anything else** uses the method for the *PC operating system* chosen in Settings:
   * **Windows** (default): Alt + numpad code. This works in almost all Windows programs and covers all Western‑European characters plus € ‘ ’ “ ” – — … ™. The dongle switches NumLock on for a moment if needed.
   * **Linux**: Ctrl+Shift+U + code. This works in most desktop apps (GTK/IBus) and covers any character, including emoji. It doesn't work in a plain text console.
3. Characters that can't be typed are skipped, and the app tells you how many. Examples: emoji on Windows, or any non‑ASCII character in the BIOS, where only plain ASCII works.

---

## 5. Configuration (firmware)

`firmware/include/config.h` or `-D` flags in `platformio.ini`:

| Option | Default | |
|---|---|---|
| `HIDLINK_NAME_PREFIX` | `"HIDlink"` | Bluetooth name prefix |
| `PAIRING_WINDOW_MS` | 60000 | How long pairing mode stays open |
| `HOLD_PAIR_MS` / `HOLD_RESET_MS` | 3000 / 10000 | Button hold times |
| `TYPE_DELAY_MS` | 4 | Delay between typed characters. Raise it if a slow BIOS or KVM drops characters. |
| `HAS_LCD` | 1 | 0 for boards without a screen |
| `USB_PRODUCT_NAME` | `"HIDlink Keyboard/Mouse"` | Name shown in Device Manager |

---

## 6. BLE protocol

Service `c0de0001-7b1e-4a5e-9d3f-4b1d0e5a1e00`

| Characteristic | UUID | Props |
|---|---|---|
| input | `c0de0002-…` | write, write‑without‑response (encrypted) |
| status | `c0de0003-…` | read, notify (encrypted) |

Each write is one packet, `[type][payload]`, with little‑endian values:

| Type | Payload | |
|---|---|---|
| `01` mouse | buttons u8, dx i16, dy i16, wheel i8, pan i8 | relative; the dongle splits large moves |
| `02` keys | mods u8, 6× key u8 | raw HID keyboard state (all zero = release) |
| `03` text | UTF‑8 bytes | typed with the selected layout (see *Special characters*) |
| `04` consumer | usage u16 | media key tap |
| `05` layout | id u8 | 0 US, 1 US‑Intl, 2 DE, 3 FR, 4 ES, 5 IT, 6 SE, 7 DK, 8 PT, 9 BR, 10 CH‑FR, 11 HU |
| `06` release | – | release everything |
| `07` OS | id u8 | 0 Windows, 1 Linux: how non‑ASCII characters are typed |

Status: `[proto=2, usb(0/1/2=BIOS), kbd LEDs, layout, #bonds, flags(bit0 pairing), OS mode]`.
The format is simple enough to write another client for, such as a Python script on a laptop.

---

## 7. Troubleshooting

| Problem | Fix |
|---|---|
| App says "Dongle refused this phone" | This phone isn't paired. Hold the dongle button 3 s until the screen shows PAIRING, then tap *Try again*. |
| Worked before, now fails after resetting the dongle | Remove `HIDlink-XXXX` in the phone's Bluetooth settings, then pair again. |
| Can't flash anymore | Hold the button while plugging in (download mode), then flash. |
| Wrong characters typed (`z`/`y` swapped, `"` missing) | Set the right layout via the layout chip. On US‑International, quotes are handled automatically. |
| Accents or € come out wrong | Check the layout chip (US‑International?) and *Settings → PC operating system*. |
| Special characters don't work on Linux | The Ctrl+Shift+U method needs a GTK/IBus desktop app. Use the US‑International layout on the PC; its characters are typed natively. |
| Mouse doesn't work in BIOS | Expected: BIOS only speaks the keyboard boot protocol. The screen shows *BIOS mode*. |
| Characters missing in BIOS or a remote console | Increase `TYPE_DELAY_MS` (e.g. 15) and rebuild. |
| Nothing on the screen | Use the right image: `-nolcd` is for boards without a screen. The normal image expects the T‑Dongle‑S3 LCD. |

---

## Project status

Early stage. The firmware builds for all three variants (PlatformIO, pioarduino 55.03.312, Arduino‑ESP32 3.3.12, NimBLE‑Arduino 2.5.1), and the Android app builds and runs. Testing on real hardware is ongoing, so expect rough edges. Issues and pull requests are welcome.

For a first bring‑up, use the `-debug` firmware: it adds a USB serial port with log output.

## Licence

HIDlink is open source under the [MIT License](LICENSE): you may use, change and share it, also commercially, as long as the copyright notice stays included.

It builds on third‑party libraries that all have permissive licences (MIT, BSD, Apache‑2.0, LGPL‑2.1 for the Arduino core). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the list.
