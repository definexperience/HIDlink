import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-side preferences (the keyboard layout lives on the dongle itself).
class Settings extends ChangeNotifier {
  double pointerSpeed = 1.4;
  bool acceleration = true;
  bool naturalScroll = true;
  bool tapToClick = true;
  bool liveTyping = false;

  SharedPreferences? _p;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    pointerSpeed = _p!.getDouble('pointerSpeed') ?? pointerSpeed;
    acceleration = _p!.getBool('acceleration') ?? acceleration;
    naturalScroll = _p!.getBool('naturalScroll') ?? naturalScroll;
    tapToClick = _p!.getBool('tapToClick') ?? tapToClick;
    liveTyping = _p!.getBool('liveTyping') ?? liveTyping;
    notifyListeners();
  }

  void update({double? pointerSpeed, bool? acceleration, bool? naturalScroll, bool? tapToClick, bool? liveTyping}) {
    if (pointerSpeed != null) {
      this.pointerSpeed = pointerSpeed;
      _p?.setDouble('pointerSpeed', pointerSpeed);
    }
    if (acceleration != null) {
      this.acceleration = acceleration;
      _p?.setBool('acceleration', acceleration);
    }
    if (naturalScroll != null) {
      this.naturalScroll = naturalScroll;
      _p?.setBool('naturalScroll', naturalScroll);
    }
    if (tapToClick != null) {
      this.tapToClick = tapToClick;
      _p?.setBool('tapToClick', tapToClick);
    }
    if (liveTyping != null) {
      this.liveTyping = liveTyping;
      _p?.setBool('liveTyping', liveTyping);
    }
    notifyListeners();
  }
}
