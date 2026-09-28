// BLE connection to the HIDlink dongle: scanning, connecting, pairing,
// status updates and sending input packets.
import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

import 'protocol.dart';

enum LinkState { idle, scanning, connecting, securing, connected }

class FoundDongle {
  final String id;
  final String name;
  final int rssi;
  FoundDongle(this.id, this.name, this.rssi);
}

class Dongle extends ChangeNotifier {
  static const _prefLastId = 'last_dongle_id';

  LinkState state = LinkState.idle;
  DongleStatus status = const DongleStatus();
  final Map<String, FoundDongle> found = {};
  String? deviceId;
  String? deviceName;
  String? lastDeviceId;
  String? error;
  bool bluetoothOn = true;

  /// Set when the dongle dropped us during setup – almost always because this
  /// phone isn't paired and the dongle isn't in pairing mode.
  bool rejectedDuringSetup = false;

  int _chunk = 19; // text bytes per packet, updated after MTU negotiation
  bool _userDisconnect = false;
  bool _textCancel = false;
  double typingProgress = -1; // -1 = not typing

  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<Uint8List>? _statusSub;
  StreamSubscription<AvailabilityState>? _availSub;

  Future<void> init() async {
    UniversalBle.queueType = QueueType.perDevice;
    UniversalBle.timeout = const Duration(seconds: 15);
    final prefs = await SharedPreferences.getInstance();
    lastDeviceId = prefs.getString(_prefLastId);

    _availSub = UniversalBle.availabilityStream.listen((s) {
      bluetoothOn = s == AvailabilityState.poweredOn;
      notifyListeners();
      if (bluetoothOn && state == LinkState.idle) startScan();
    });
    final s = await UniversalBle.getBluetoothAvailabilityState();
    bluetoothOn = s == AvailabilityState.poweredOn || s == AvailabilityState.unknown;
    if (bluetoothOn) await startScan();
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------
  Future<void> startScan() async {
    if (state == LinkState.scanning || state == LinkState.connecting) return;
    found.clear();
    error = null;
    state = LinkState.scanning;
    notifyListeners();

    await _scanSub?.cancel();
    _scanSub = UniversalBle.scanStream.listen(_onScanResult);
    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: [Hid.serviceUuid]),
        platformConfig: PlatformConfig(
          android: AndroidOptions(
            legacy: true,
            scanMode: AndroidScanMode.lowLatency,
            requestLocationPermission: false,
          ),
        ),
      );
    } catch (e) {
      error = 'Could not start scanning: $e';
      state = LinkState.idle;
      notifyListeners();
    }
  }

  void _onScanResult(BleDevice d) {
    if (state != LinkState.scanning) return;
    final name = (d.name?.isNotEmpty ?? false) ? d.name! : 'HIDlink';
    found[d.deviceId] = FoundDongle(d.deviceId, name, d.rssi ?? -100);
    notifyListeners();
    // Pair-once workflow: reconnect automatically to the dongle used last time
    if (d.deviceId == lastDeviceId && !rejectedDuringSetup) {
      connect(d.deviceId, name);
    }
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
    if (state == LinkState.scanning) {
      state = LinkState.idle;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Connecting
  // ---------------------------------------------------------------------------
  Future<void> connect(String id, String name) async {
    if (state == LinkState.connecting || state == LinkState.securing || state == LinkState.connected) return;
    await stopScan();
    deviceId = id;
    deviceName = name;
    error = null;
    rejectedDuringSetup = false;
    _userDisconnect = false;
    state = LinkState.connecting;
    notifyListeners();

    await _connSub?.cancel();
    _connSub = UniversalBle.connectionStream(id).listen((connected) {
      if (!connected) _onDisconnected();
    });

    try {
      await UniversalBle.connect(id, timeout: const Duration(seconds: 12));
      state = LinkState.securing;
      notifyListeners();

      await UniversalBle.discoverServices(id);

      if (!kIsWeb && Platform.isAndroid) {
        try {
          await UniversalBle.requestConnectionPriority(id, BleConnectionPriority.highPerformance);
        } catch (_) {}
      }
      await _negotiateMtu(id);

      // Reading the (encrypted) status characteristic triggers pairing on a
      // new phone, or silent re-encryption on a phone that is already paired.
      Uint8List? v;
      for (var attempt = 0; attempt < 3 && v == null; attempt++) {
        if (state != LinkState.securing) return; // dropped meanwhile
        try {
          v = await UniversalBle.read(id, Hid.serviceUuid, Hid.statusUuid,
              timeout: const Duration(seconds: 20));
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }
      if (v == null) throw Exception('pairing/encryption failed');
      status = DongleStatus.parse(v);

      await _statusSub?.cancel();
      _statusSub = UniversalBle.characteristicValueStream(id, Hid.statusUuid).listen((v) {
        status = DongleStatus.parse(v);
        notifyListeners();
      });
      await UniversalBle.subscribeNotifications(id, Hid.serviceUuid, Hid.statusUuid);

      state = LinkState.connected;
      lastDeviceId = id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastId, id);
      notifyListeners();
    } catch (e) {
      if (state == LinkState.idle) return; // already handled in _onDisconnected
      error = 'Connection failed: ${_short(e)}';
      await _cleanup(disconnect: true);
      state = LinkState.idle;
      notifyListeners();
    }
  }

  Future<void> _negotiateMtu(String id) async {
    int mtu = 23;
    try {
      mtu = await UniversalBle.requestMtu(id, 247);
    } catch (_) {
      if (!kIsWeb && Platform.isIOS) mtu = 185; // iOS negotiates by itself
    }
    // payload = ATT MTU - 3 (ATT header) - 1 (our packet type)
    _chunk = (mtu - 4).clamp(19, 240).toInt();
  }

  void _onDisconnected() {
    if (state == LinkState.idle) return;
    final wasConnecting = state == LinkState.connecting;
    final wasSecuring = state == LinkState.securing;
    _cleanup(disconnect: false);
    status = const DongleStatus();
    if (!_userDisconnect) {
      if (wasSecuring) {
        // connected fine, then dropped while pairing/encrypting: the dongle
        // does that to phones it doesn't know (outside pairing mode)
        rejectedDuringSetup = true;
      } else {
        error = wasConnecting ? 'Could not connect to the dongle' : 'Connection lost';
      }
    }
    state = LinkState.idle;
    notifyListeners();
    // lost an established link: look for the dongle again and reconnect
    if (!_userDisconnect && !wasConnecting && !wasSecuring) {
      Future.delayed(const Duration(milliseconds: 800), startScan);
    }
  }

  Future<void> _cleanup({required bool disconnect}) async {
    _textCancel = true;
    await _statusSub?.cancel();
    _statusSub = null;
    await _connSub?.cancel();
    _connSub = null;
    _mouseTimer?.cancel();
    _mouseTimer = null;
    final id = deviceId;
    if (disconnect && id != null) {
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    _userDisconnect = true;
    final id = deviceId;
    if (id != null && state == LinkState.connected) {
      try {
        await _write(Hid.release(), withResponse: true);
      } catch (_) {}
    }
    await _cleanup(disconnect: true);
    state = LinkState.idle;
    status = const DongleStatus();
    notifyListeners();
  }

  /// Forget the remembered dongle (no auto-connect on next start).
  Future<void> forgetDongle({bool removePhonePairing = false}) async {
    final id = deviceId ?? lastDeviceId;
    await disconnect();
    if (removePhonePairing && id != null && !kIsWeb && Platform.isAndroid) {
      try {
        await UniversalBle.unpair(id);
      } catch (_) {}
    }
    lastDeviceId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefLastId);
    notifyListeners();
  }

  void retryAfterRejection() {
    rejectedDuringSetup = false;
    error = null;
    startScan();
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------
  bool get isConnected => state == LinkState.connected;

  Future<void> _write(Uint8List data, {bool withResponse = false}) async {
    final id = deviceId;
    if (id == null || state != LinkState.connected) return;
    await UniversalBle.write(id, Hid.serviceUuid, Hid.inputUuid, data, withoutResponse: !withResponse);
  }

  Future<void> _safeWrite(Uint8List data, {bool withResponse = false}) async {
    try {
      await _write(data, withResponse: withResponse);
    } catch (e) {
      debugPrint('write failed: $e');
    }
  }

  // --- keyboard ---
  Future<void> keyDown(int mods, int key) => _safeWrite(Hid.keys(mods, key == 0 ? [] : [key]));
  Future<void> keyUp() => _safeWrite(Hid.keys(0, const []));

  Future<void> tap(int mods, int key) async {
    await keyDown(mods, key);
    await keyUp();
  }

  Future<void> sendConsumer(int usage) => _safeWrite(Hid.consumer(usage));

  Future<void> setLayout(int id) async {
    await _safeWrite(Hid.layout(id), withResponse: true);
  }

  Future<void> releaseAll() => _safeWrite(Hid.release(), withResponse: true);

  Future<void> setOsMode(int id) async {
    await _safeWrite(Hid.osMode(id), withResponse: true);
  }

  /// Types [text] on the PC. Returns the number of characters that were
  /// skipped because they can't be typed (e.g. emoji on Windows).
  Future<int> typeText(String text, {bool showProgress = true}) async {
    // Split into characters, drop what can't be typed, group into packets
    // without ever cutting a multi-byte UTF-8 character in half.
    final packets = <List<int>>[];
    final costs = <int>[]; // rough typing time per packet (ms)
    var cur = <int>[];
    var cost = 0;
    var skipped = 0;
    for (final r in text.runes) {
      if (!Typable.check(r, osMode: status.osMode, bios: status.biosMode)) {
        skipped++;
        continue;
      }
      if (r == 0x0D) continue; // CR: LF already gives Enter
      final b = utf8.encode(String.fromCharCode(r));
      if (cur.length + b.length > _chunk) {
        packets.add(cur);
        costs.add(cost);
        cur = <int>[];
        cost = 0;
      }
      cur.addAll(b);
      cost += r < 0x80 ? 12 : 60; // Alt codes / dead keys take longer
    }
    if (cur.isNotEmpty) {
      packets.add(cur);
      costs.add(cost);
    }
    if (packets.isEmpty) return skipped;

    _textCancel = false;
    if (showProgress) {
      typingProgress = 0;
      notifyListeners();
    }
    try {
      for (var i = 0; i < packets.length; i++) {
        if (_textCancel || !isConnected) break;
        await _write(Hid.text(packets[i]), withResponse: true);
        if (showProgress) {
          typingProgress = (i + 1) / packets.length;
          notifyListeners();
        }
        // Pace long texts at roughly the dongle's typing speed so its
        // buffer never overflows.
        if (i + 1 < packets.length) {
          await Future.delayed(Duration(milliseconds: costs[i]));
        }
      }
    } catch (e) {
      error = 'Typing interrupted: ${_short(e)}';
    }
    if (showProgress) {
      typingProgress = -1;
      notifyListeners();
    }
    return skipped;
  }

  void cancelTyping() => _textCancel = true;

  // --- mouse ---
  // Movement is accumulated and sent at a fixed rate (≈100 Hz) so a slow
  // BLE link never builds up a backlog: the pointer stays responsive.
  double _accX = 0, _accY = 0, _accWheel = 0, _accPan = 0;
  int _buttons = 0; // latest wanted button state
  int _sentButtons = 0; // state the dongle has
  final List<int> _buttonEvents = []; // pending changes, sent in order
  bool _mouseBusy = false;
  Timer? _mouseTimer;

  int get mouseButtons => _buttons;

  void moveMouse(double dx, double dy) {
    _accX += dx;
    _accY += dy;
    _ensureMouseTimer();
  }

  void scroll(double wheel, double pan) {
    _accWheel += wheel;
    _accPan += pan;
    _ensureMouseTimer();
  }

  void setButtons(int buttons) {
    if (buttons == _buttons) return;
    _buttons = buttons;
    _buttonEvents.add(buttons);
    notifyListeners(); // for the pressed look of the on-screen buttons
    _ensureMouseTimer();
    _mouseTick(); // send button changes right away
  }

  void click(int button) {
    setButtons(_buttons | button);
    setButtons(_buttons & ~button);
  }

  void _ensureMouseTimer() {
    _mouseTimer ??= Timer.periodic(const Duration(milliseconds: 10), (_) => _mouseTick());
  }

  Future<void> _mouseTick() async {
    if (_mouseBusy || !isConnected) return;
    final dx = _accX.truncate(), dy = _accY.truncate();
    final wh = _accWheel.truncate(), pn = _accPan.truncate();
    if (dx == 0 && dy == 0 && wh == 0 && pn == 0 && _buttonEvents.isEmpty) {
      _mouseTimer?.cancel(); // idle until the next movement
      _mouseTimer = null;
      return;
    }
    _accX -= dx;
    _accY -= dy;
    _accWheel -= wh;
    _accPan -= pn;
    final b = _buttonEvents.isNotEmpty ? _buttonEvents.removeAt(0) : _sentButtons;
    _mouseBusy = true;
    try {
      // button changes go "with response" so they can never get lost
      await _write(Hid.mouse(b, dx, dy, wh, pn), withResponse: b != _sentButtons);
      _sentButtons = b;
    } catch (e) {
      debugPrint('mouse write failed: $e');
    } finally {
      _mouseBusy = false;
    }
  }

  String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _availSub?.cancel();
    _cleanup(disconnect: true);
    super.dispose();
  }
}
