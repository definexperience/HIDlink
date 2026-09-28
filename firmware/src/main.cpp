// ===========================================================================
// HIDlink – BLE to USB keyboard/mouse dongle for the LilyGO T-Dongle-S3
//
//   phone app --BLE--> dongle --USB HID--> PC
//
// The PC sees a standard USB keyboard + mouse (+ media keys). No drivers.
// The keyboard supports the USB boot protocol, so it also works in BIOS/UEFI.
// ===========================================================================
#include <Arduino.h>
#include <FS.h>  // not used directly; the core USB library needs it on the include path
#include <Preferences.h>
#include <NimBLEDevice.h>
#include "USB.h"
#include "USBHIDKeyboard.h"
#include "USBHIDMouse.h"
#include "USBHIDConsumerControl.h"
#include "esp32-hal-tinyusb.h"
#include "esp_mac.h"

#include "config.h"
#include "protocol.h"
#include "charmap.h"
#include "ui.h"

#if ARDUINO_USB_MODE != 0
#error "HIDlink needs USB-OTG (TinyUSB) mode: build with -DARDUINO_USB_MODE=0"
#endif

// The keyboard MUST be the first HID object: the first one decides the USB
// interface protocol, and a keyboard enables BIOS (boot protocol) support.
USBHIDKeyboard Keyboard;
USBHIDRelativeMouse Mouse;
USBHIDConsumerControl Consumer;

// ---------------------------------------------------------------------------
// Keyboard layouts
// ---------------------------------------------------------------------------
struct LayoutInfo {
  const uint8_t *map;
  const char *name;
};
static const LayoutInfo LAYOUTS[LAYOUT_COUNT] = {
  {KeyboardLayout_en_US, "US"},       {KeyboardLayout_en_US, "US-Intl"}, {KeyboardLayout_de_DE, "DE"},
  {KeyboardLayout_fr_FR, "FR"},       {KeyboardLayout_es_ES, "ES"},      {KeyboardLayout_it_IT, "IT"},
  {KeyboardLayout_sv_SE, "SE"},       {KeyboardLayout_da_DK, "DK"},      {KeyboardLayout_pt_PT, "PT"},
  {KeyboardLayout_pt_BR, "BR"},       {KeyboardLayout_fr_CH, "CH-FR"},   {KeyboardLayout_hu_HU, "HU"},
};

// ---------------------------------------------------------------------------
// State shared between the BLE task and loop()
// ---------------------------------------------------------------------------
struct Packet {
  uint16_t len;
  uint8_t data[250];
};
static QueueHandle_t packetQueue;

static Preferences prefs;
static char deviceName[24];
static uint8_t layoutId = LAYOUT_EN_US;
static uint8_t osMode = OS_WINDOWS;

static NimBLEServer *server = nullptr;
static NimBLECharacteristic *statusChar = nullptr;

static volatile bool bleConnected = false;
static volatile bool bleSecured = false;
static volatile uint16_t bleConnHandle = 0;
static volatile uint32_t bleConnectedAt = 0;
static volatile uint32_t pairingUntil = 0;  // millis() deadline, 0 = off
static volatile bool pairingSucceeded = false;
static volatile bool authRejected = false;
static volatile uint8_t kbdLeds = 0;
static volatile bool statusDirty = true;
static bool typing = false;

static char uiMsg[24] = "";
static uint32_t uiMsgUntil = 0;

static void showMessage(const char *m, uint32_t ms = 2500) {
  strlcpy(uiMsg, m, sizeof uiMsg);
  uiMsgUntil = millis() + ms;
}

static bool pairingActive() { return pairingUntil != 0 && (int32_t)(pairingUntil - millis()) > 0; }

// USB report protocol = normal OS. Boot protocol = BIOS; then only plain
// keyboard reports are allowed (mouse/media reports would be misread).
static bool usbReportMode() { return tud_hid_n_get_protocol(0) == HID_PROTOCOL_REPORT; }
static uint8_t usbState() {
  if (!USB) return 0;
  return usbReportMode() ? 1 : 2;
}

// ---------------------------------------------------------------------------
// Pairing / security
// ---------------------------------------------------------------------------
static void applySecurity() {
#if REQUIRE_BONDING
  // Just-Works pairing (no code). Bonding (= remembering the phone) is only
  // allowed while pairing mode is open; otherwise only known phones get in.
  NimBLEDevice::setSecurityAuth(pairingActive(), false, true);
#else
  NimBLEDevice::setSecurityAuth(false, false, false);
#endif
}

static void startPairing() {
  pairingUntil = millis() + PAIRING_WINDOW_MS;
  if (pairingUntil == 0) pairingUntil = 1;
  applySecurity();
  statusDirty = true;
}

static void stopPairing() {
  pairingUntil = 0;
  applySecurity();
  statusDirty = true;
}

// ---------------------------------------------------------------------------
// BLE callbacks (run in the NimBLE host task – keep them short)
// ---------------------------------------------------------------------------
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *s, NimBLEConnInfo &info) override {
    bleConnHandle = info.getConnHandle();
    bleConnectedAt = millis();
    bleSecured = false;
    bleConnected = true;
    // 7.5–15 ms connection interval for a responsive mouse, 2 s supervision timeout
    s->updateConnParams(info.getConnHandle(), 6, 12, 0, 200);
#if REQUIRE_BONDING
    // Ask the phone to encrypt. A known phone re-encrypts silently with the
    // stored key; a new phone only gets bonded while pairing mode is open.
    NimBLEDevice::startSecurity(info.getConnHandle());
#else
    bleSecured = true;
#endif
    statusDirty = true;
  }

  void onDisconnect(NimBLEServer *, NimBLEConnInfo &, int reason) override {
    bleConnected = false;
    bleSecured = false;
    // make sure nothing stays pressed on the PC
    Packet p{1, {PKT_RELEASE}};
    xQueueSend(packetQueue, &p, 0);
    statusDirty = true;
    DBG("BLE disconnected, reason %d\n", reason);
  }

  void onAuthenticationComplete(NimBLEConnInfo &info) override {
#if REQUIRE_BONDING
    if (!info.isEncrypted() || !info.isBonded()) {
      DBG("BLE auth rejected (enc=%d bonded=%d)\n", info.isEncrypted(), info.isBonded());
      authRejected = true;
      server->disconnect(info.getConnHandle());
      return;
    }
    if (pairingActive()) pairingSucceeded = true;
#endif
    bleSecured = true;
    statusDirty = true;
    DBG("BLE secured: %s\n", info.getIdAddress().toString().c_str());
  }
};

class InputCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *c, NimBLEConnInfo &info) override {
#if REQUIRE_BONDING
    if (!info.isEncrypted() || !info.isBonded()) return;
#endif
    const NimBLEAttValue &v = c->getValue();
    if (v.size() == 0) return;
    Packet p;
    p.len = min<size_t>(v.size(), sizeof(p.data));
    memcpy(p.data, v.data(), p.len);
    // Text is sent with "write with response" by the app, so it is naturally
    // flow-controlled; a short wait here is fine. Mouse packets never wait.
    xQueueSend(packetQueue, &p, p.data[0] == PKT_TEXT ? pdMS_TO_TICKS(50) : 0);
  }
};

static void updateStatusChar(bool notify) {
  if (!statusChar) return;
  uint8_t v[7] = {
    HIDLINK_PROTOCOL_VERSION,
    usbState(),
    kbdLeds,
    layoutId,
    (uint8_t)NimBLEDevice::getNumBonds(),
    (uint8_t)((pairingActive() ? 1 : 0) | (typing ? 2 : 0)),
    osMode,
  };
  statusChar->setValue(v, sizeof v);
  if (notify && bleConnected && bleSecured) statusChar->notify();
}

static void bleBegin() {
  NimBLEDevice::init(deviceName);
  NimBLEDevice::setPower(9);  // dBm
  NimBLEDevice::setMTU(247);
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);  // "Just Works"
  // Exchange encryption + identity keys, so a paired phone is recognised
  // again even though it changes its Bluetooth address every few minutes.
  NimBLEDevice::setSecurityInitKey(BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID);
  NimBLEDevice::setSecurityRespKey(BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID);
  applySecurity();

  server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  server->advertiseOnDisconnect(true);

  NimBLEService *svc = server->createService(HIDLINK_SERVICE_UUID);
#if REQUIRE_BONDING
  const uint32_t inProps = NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR | NIMBLE_PROPERTY::WRITE_ENC;
  const uint32_t stProps = NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ_ENC;
#else
  const uint32_t inProps = NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR;
  const uint32_t stProps = NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY;
#endif
  NimBLECharacteristic *input = svc->createCharacteristic(HIDLINK_INPUT_UUID, inProps, 250);
  input->setCallbacks(new InputCallbacks());
  statusChar = svc->createCharacteristic(HIDLINK_STATUS_UUID, stProps, 16);
  updateStatusChar(false);
  server->start();

  // Service UUID in the advertisement (the app filters on it), name in the
  // scan response (both together don't fit in 31 bytes).
  NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData advData;
  advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  advData.addServiceUUID(HIDLINK_SERVICE_UUID);
  NimBLEAdvertisementData scanData;
  scanData.setName(deviceName);
  adv->setAdvertisementData(advData);
  adv->setScanResponseData(scanData);
  adv->start();
}

// ---------------------------------------------------------------------------
// USB HID output
// ---------------------------------------------------------------------------
static void onKeyboardEvent(void *, esp_event_base_t base, int32_t id, void *data) {
  if (base == ARDUINO_USB_HID_KEYBOARD_EVENTS && id == ARDUINO_USB_HID_KEYBOARD_LED_EVENT) {
    kbdLeds = ((arduino_usb_hid_keyboard_event_data_t *)data)->leds;
    statusDirty = true;
  }
}

static void setLayout(uint8_t id, bool save) {
  if (id >= LAYOUT_COUNT) return;
  layoutId = id;
  Keyboard.begin(LAYOUTS[id].map);
  if (save) prefs.putUChar("layout", id);
  statusDirty = true;
}

static uint8_t mouseButtons = 0;
static int32_t accX = 0, accY = 0, accWheel = 0, accPan = 0;

static inline int8_t take8(int32_t &acc) {
  int32_t v = constrain(acc, -127, 127);
  acc -= v;
  return (int8_t)v;
}

static void flushMouse() {
  if (!usbReportMode()) {  // BIOS: no mouse
    accX = accY = accWheel = accPan = 0;
    return;
  }
  while (accX || accY || accWheel || accPan) {
    Mouse.move(take8(accX), take8(accY), take8(accWheel), take8(accPan));
  }
}

static void releaseEverything() {
  flushMouse();
  KeyReport empty = {};
  Keyboard.sendReport(&empty);
  Keyboard.releaseAll();
  if (usbReportMode()) {
    Mouse.buttons(0);
    Consumer.release();
  }
  mouseButtons = 0;
}

// Send one key stroke (press + release) as a raw report
static void strokeRaw(uint8_t mods, uint8_t key) {
  KeyReport r = {};
  r.modifiers = mods;
  if (mods && key) Keyboard.sendReport(&r);  // modifiers first: safer for some hosts
  r.keys[0] = key;
  Keyboard.sendReport(&r);
  KeyReport empty = {};
  Keyboard.sendReport(&empty);
}

static const uint8_t KP_DIGIT[10] = {0x62, 0x59, 0x5A, 0x5B, 0x5C, 0x5D, 0x5E, 0x5F, 0x60, 0x61};  // keypad 0..9

// Windows: hold Alt, type 0nnn on the numeric keypad (Windows-1252 code)
static bool typeAltCode(uint8_t code) {
  const bool numWasOff = !(kbdLeds & 0x01);
  if (numWasOff) {  // keypad digits only work with NumLock on
    strokeRaw(0, 0x53);
    delay(30);
  }
  char digits[5];
  snprintf(digits, sizeof digits, "0%03u", code);
  KeyReport r = {};
  r.modifiers = 0x04;  // left Alt
  Keyboard.sendReport(&r);
  for (int i = 0; i < 4; i++) {
    r.keys[0] = KP_DIGIT[digits[i] - '0'];
    Keyboard.sendReport(&r);
    r.keys[0] = 0;
    Keyboard.sendReport(&r);
  }
  KeyReport empty = {};
  Keyboard.sendReport(&empty);  // releasing Alt inserts the character
  if (numWasOff) {
    delay(10);
    strokeRaw(0, 0x53);  // restore NumLock
  }
  return true;
}

// Linux (GTK / IBus): Ctrl+Shift+U, hex code, Space
static bool typeLinuxUnicode(uint32_t cp) {
  strokeRaw(0x01 | 0x02, 0x18);  // Ctrl+Shift+U
  delay(15);
  char hex[9];
  snprintf(hex, sizeof hex, "%lx", (unsigned long)cp);
  for (char *h = hex; *h; h++) Keyboard.write((uint8_t)*h);
  Keyboard.write(' ');
  return true;
}

// Type one non-ASCII character. Returns false if it can't be typed.
static bool typeSpecial(uint32_t cp) {
  if (cp == 0xA0) {  // no-break space -> normal space
    Keyboard.write(' ');
    return true;
  }
  if (layoutId == LAYOUT_US_INTL) {
    if (const IntlChar *c = findUsIntl(cp)) {
      if (c->dead) {
        Keyboard.write((uint8_t)c->dead);
        Keyboard.write((uint8_t)c->base);
      } else {
        strokeRaw(c->mods, c->key);
      }
      return true;
    }
  }
  if (osMode == OS_WINDOWS) {
    uint8_t code = toCp1252(cp);
    return code ? typeAltCode(code) : false;
  }
  return typeLinuxUnicode(cp);
}

// Decode UTF-8 and type it with the selected layout
static void typeText(const uint8_t *s, size_t n) {
  const bool usIntl = layoutId == LAYOUT_US_INTL;
  typing = true;
  statusDirty = true;
  size_t i = 0;
  while (i < n) {
    uint32_t cp = s[i];
    size_t len = 1;
    if (cp >= 0xF0 && i + 3 < n) {
      cp = ((cp & 0x07) << 18) | ((s[i + 1] & 0x3F) << 12) | ((s[i + 2] & 0x3F) << 6) | (s[i + 3] & 0x3F);
      len = 4;
    } else if (cp >= 0xE0 && i + 2 < n) {
      cp = ((cp & 0x0F) << 12) | ((s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F);
      len = 3;
    } else if (cp >= 0xC0 && i + 1 < n) {
      cp = ((cp & 0x1F) << 6) | (s[i + 1] & 0x3F);
      len = 2;
    } else if (cp >= 0x80) {
      cp = 0;  // stray continuation byte: ignore
    }
    i += len;

    if (cp == 0 || cp == '\r') continue;
    if (cp == '\n') Keyboard.write(KEY_RETURN);
    else if (cp == '\t') Keyboard.write(KEY_TAB);
    else if (cp < 0x80) {
      Keyboard.write((uint8_t)cp);
      // US-International: ' " ` ~ ^ are dead keys; a space makes them literal
      if (usIntl && (cp == '\'' || cp == '"' || cp == '`' || cp == '~' || cp == '^')) Keyboard.write(' ');
    } else if (usbReportMode()) {  // BIOS can only do plain ASCII
      typeSpecial(cp);
    }
    if (TYPE_DELAY_MS) delay(TYPE_DELAY_MS);
  }
  typing = false;
  statusDirty = true;
}

static void setOsMode(uint8_t m, bool save) {
  if (m >= OS_COUNT) return;
  osMode = m;
  if (save) prefs.putUChar("os", m);
  statusDirty = true;
}

static void handlePacket(const Packet &p) {
  const uint8_t *d = p.data;
  const uint8_t type = d[0];

  if (type == PKT_MOUSE) {
    if (p.len < 8) return;
    uint8_t buttons = d[1];
    int16_t dx = (int16_t)(d[2] | (d[3] << 8));
    int16_t dy = (int16_t)(d[4] | (d[5] << 8));
    int8_t wheel = (int8_t)d[6];
    int8_t pan = (int8_t)d[7];
    if (buttons != mouseButtons) {
      flushMouse();  // movement before the click belongs to the old state
      mouseButtons = buttons;
      if (usbReportMode()) Mouse.buttons(buttons);
    }
    accX += dx;
    accY += dy;
    accWheel += wheel;
    accPan += pan;
    return;  // movement is flushed in batches by the caller
  }

  flushMouse();
  switch (type) {
    case PKT_KEYS: {
      if (p.len < 8) return;
      KeyReport r = {};
      r.modifiers = d[1];
      memcpy(r.keys, d + 2, 6);
      Keyboard.sendReport(&r);
      break;
    }
    case PKT_TEXT:
      typeText(d + 1, p.len - 1);
      break;
    case PKT_CONSUMER:
      if (p.len < 3 || !usbReportMode()) return;
      Consumer.press((uint16_t)(d[1] | (d[2] << 8)));
      delay(10);
      Consumer.release();
      break;
    case PKT_LAYOUT:
      if (p.len >= 2) setLayout(d[1], true);
      break;
    case PKT_RELEASE:
      releaseEverything();
      break;
    case PKT_OSMODE:
      if (p.len >= 2) setOsMode(d[1], true);
      break;
  }
}

// ---------------------------------------------------------------------------
// Button: short press = info page, hold 3 s = pairing, hold 10 s = forget all
// ---------------------------------------------------------------------------
static bool btnDown = false;
static uint32_t btnDownAt = 0;
static bool infoPage = false;
static uint32_t infoUntil = 0;

static void forgetAllPhones() {
  if (bleConnected) server->disconnect(bleConnHandle);
  NimBLEDevice::deleteAllBonds();
  showMessage("all phones forgotten", 3000);
  startPairing();
}

static uint32_t pollButton() {
  const uint32_t now = millis();
  const bool down = digitalRead(PIN_BUTTON) == LOW;
  if (down && !btnDown) btnDownAt = now;
  uint32_t held = down ? now - btnDownAt : 0;
  if (!down && btnDown) {
    uint32_t d = now - btnDownAt;
    if (d >= HOLD_RESET_MS) forgetAllPhones();
    else if (d >= HOLD_PAIR_MS) startPairing();
    else if (d >= 40) {
      if (pairingActive()) stopPairing();  // short press cancels pairing
      else {
        infoPage = !infoPage;
        infoUntil = now + 10000;
      }
    }
  }
  btnDown = down;
  if (infoPage && (int32_t)(now - infoUntil) > 0) infoPage = false;
  return held;
}

// ---------------------------------------------------------------------------
// Status LED
// ---------------------------------------------------------------------------
static void updateLed() {
  const uint32_t now = millis();
  if (pairingActive()) {
    bool on = (now / 250) % 2;
    ledSet(0, 0, on ? 255 : 0);  // blinking blue
  } else if (bleConnected && bleSecured) {
    ledSet(0, typing ? 255 : 90, 0);  // green
  } else if (bleConnected) {
    ledSet(160, 110, 0);  // yellow: securing
  } else {
    ledSet(0, 0, 0);
  }
}

// ---------------------------------------------------------------------------
void setup() {
#ifdef HIDLINK_DEBUG
  Serial.begin(115200);
#endif
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  ledBegin();
  displayBegin();

  packetQueue = xQueueCreate(48, sizeof(Packet));

  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_BT);
  snprintf(deviceName, sizeof deviceName, "%s-%02X%02X", HIDLINK_NAME_PREFIX, mac[4], mac[5]);

  prefs.begin("hidlink", false);
  uint8_t savedLayout = prefs.getUChar("layout", LAYOUT_US_INTL);
  setOsMode(prefs.getUChar("os", OS_WINDOWS), false);

  // USB HID
  USB.productName(USB_PRODUCT_NAME);
  USB.manufacturerName(USB_MANUFACTURER_NAME);
  Keyboard.onEvent(onKeyboardEvent);
  Keyboard.setShiftKeyReports(true);  // separate Shift report: safer for BIOS
  setLayout(savedLayout < LAYOUT_COUNT ? savedLayout : LAYOUT_US_INTL, false);
  Mouse.begin();
  Consumer.begin();
  USB.begin();

  bleBegin();

#if REQUIRE_BONDING
  // First use: no phone paired yet -> open pairing automatically.
  if (NimBLEDevice::getNumBonds() == 0) startPairing();
#endif
  DBG("%s ready, %d bond(s)\n", deviceName, NimBLEDevice::getNumBonds());
}

void loop() {
  // 1. Drain BLE packets -> USB. Mouse movement is merged per batch.
  Packet p;
  bool any = false;
  while (xQueueReceive(packetQueue, &p, 0) == pdTRUE) {
    handlePacket(p);
    any = true;
  }
  if (any) flushMouse();

  const uint32_t now = millis();

  // 2. Pairing mode bookkeeping
  if (pairingUntil && !pairingActive()) stopPairing();
  if (pairingSucceeded) {
    pairingSucceeded = false;
    stopPairing();
    showMessage("phone paired!");
  }
  if (authRejected) {
    authRejected = false;
    showMessage("unknown phone: pair", 4000);
  }

  // 3. Drop phones that don't finish security in time
#if REQUIRE_BONDING
  if (bleConnected && !bleSecured && now - bleConnectedAt > AUTH_TIMEOUT_MS) {
    server->disconnect(bleConnHandle);
    bleConnectedAt = now;  // don't hammer disconnect
    showMessage(pairingActive() ? "pairing failed" : "unknown phone");
  }
#endif

  // 4. Status characteristic (USB state and keyboard LEDs can change anytime)
  static uint8_t lastUsb = 255;
  static uint32_t lastStatusAt = 0;
  uint8_t u = usbState();
  if (u != lastUsb) {
    lastUsb = u;
    statusDirty = true;
  }
  if (statusDirty && now - lastStatusAt > 50) {
    statusDirty = false;
    lastStatusAt = now;
    updateStatusChar(true);
  }

  // 5. UI
  uint32_t held = pollButton();
  static UiState last;
  static uint32_t lastDraw = 0;
  UiState s;
  s.name = deviceName;
  s.layout = LAYOUTS[layoutId].name;
  s.usb = u;
  s.ble = !bleConnected ? BleState::Advertising : (bleSecured ? BleState::Connected : BleState::Securing);
  s.pairingSecsLeft = pairingActive() ? (pairingUntil - now + 999) / 1000 : 0;
  s.bonds = NimBLEDevice::getNumBonds();
  s.caps = kbdLeds & 0x02;
  s.typing = typing;
  s.holdMs = held;
  s.infoPage = infoPage;
  s.open = !REQUIRE_BONDING;
  if (uiMsg[0] && (int32_t)(now - uiMsgUntil) < 0) strlcpy(s.msg, uiMsg, sizeof s.msg);
  if (!(s == last) || now - lastDraw > 1000) {
    displayRender(s);
    last = s;
    lastDraw = now;
  }
  updateLed();

  delay(1);
}
