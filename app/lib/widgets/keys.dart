import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dongle.dart';
import '../protocol.dart';

/// Sticky modifier keys. Tap = applies to the next key only,
/// long-press = locked until tapped again.
class Modifiers extends ChangeNotifier {
  int oneShot = 0;
  int locked = 0;

  int get active => oneShot | locked;

  void tap(int bit) {
    if ((locked & bit) != 0) {
      locked &= ~bit;
    } else {
      oneShot ^= bit;
    }
    notifyListeners();
  }

  void lock(int bit) {
    locked |= bit;
    oneShot &= ~bit;
    notifyListeners();
  }

  /// Returns the modifiers for a key press and clears the one-shot ones.
  int consume() {
    final m = active;
    if (oneShot != 0) {
      oneShot = 0;
      notifyListeners();
    }
    return m;
  }

  void clear() {
    oneShot = 0;
    locked = 0;
    notifyListeners();
  }
}

/// A key that is held on the PC for as long as your finger is on it,
/// so the PC's own auto-repeat works (arrows, backspace, ...).
class HoldKey extends StatefulWidget {
  final String label;
  final IconData? icon;
  final int keyCode;
  final int extraMods;
  final Dongle dongle;
  final Modifiers mods;
  final double height;

  const HoldKey({
    super.key,
    required this.label,
    required this.keyCode,
    required this.dongle,
    required this.mods,
    this.icon,
    this.extraMods = 0,
    this.height = 40,
  });

  @override
  State<HoldKey> createState() => _HoldKeyState();
}

class _HoldKeyState extends State<HoldKey> {
  bool _down = false;

  void _press() {
    HapticFeedback.selectionClick();
    setState(() => _down = true);
    widget.dongle.keyDown(widget.mods.consume() | widget.extraMods, widget.keyCode);
  }

  void _release() {
    if (!_down) return;
    setState(() => _down = false);
    widget.dongle.keyUp();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (_) => _press(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: Container(
        height: widget.height,
        margin: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: _down ? cs.primary.withValues(alpha: 0.4) : cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: cs.outlineVariant),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: widget.icon != null
            ? Icon(widget.icon, size: 20)
            : FittedBox(
                child: Text(widget.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
      ),
    );
  }
}

/// One-tap key combination (e.g. Ctrl+Alt+Del).
class ComboKey extends StatelessWidget {
  final String label;
  final int mods;
  final int keyCode;
  final Dongle dongle;
  final bool danger;

  const ComboKey({
    super.key,
    required this.label,
    required this.mods,
    required this.keyCode,
    required this.dongle,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: Material(
        color: danger ? cs.errorContainer : cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () async {
            HapticFeedback.selectionClick();
            // press modifiers first, then the key: some targets (BIOS, RDP)
            // are picky about everything arriving in one report
            await dongle.keyDown(mods, 0);
            await dongle.keyDown(mods, keyCode);
            await dongle.keyUp();
          },
          child: Container(
            height: 40,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ctrl / Shift / Alt / Win / AltGr toggles.
class ModifierBar extends StatelessWidget {
  final Modifiers mods;
  const ModifierBar({super.key, required this.mods});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget m(String label, int bit) {
      final isLocked = (mods.locked & bit) != 0;
      final isOn = (mods.active & bit) != 0;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(2.5),
          child: Material(
            color: isLocked ? cs.primary : (isOn ? cs.primary.withValues(alpha: 0.45) : cs.surfaceContainerHighest.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () {
                HapticFeedback.selectionClick();
                mods.tap(bit);
              },
              onLongPress: () {
                HapticFeedback.mediumImpact();
                mods.lock(bit);
              },
              child: Container(
                height: 38,
                alignment: Alignment.center,
                child: Text(
                  isLocked ? '$label 🔒' : label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isLocked ? cs.onPrimary : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      m('Ctrl', Mod.ctrl),
      m('Shift', Mod.shift),
      m('Alt', Mod.alt),
      m('Win', Mod.gui),
      m('AltGr', Mod.rAlt),
    ]);
  }
}

/// Tabbed panel with special keys, F-keys, navigation, shortcuts and media.
class KeyPanel extends StatelessWidget {
  final Dongle dongle;
  final Modifiers mods;
  const KeyPanel({super.key, required this.dongle, required this.mods});

  Widget _grid(List<Widget> keys, {int columns = 4}) {
    final rows = <Widget>[];
    for (var i = 0; i < keys.length; i += columns) {
      final row = keys.sublist(i, (i + columns).clamp(0, keys.length).toInt());
      while (row.length < columns) {
        row.add(const SizedBox());
      }
      rows.add(Row(children: row.map((k) => Expanded(child: k)).toList()));
    }
    return SingleChildScrollView(child: Column(children: rows));
  }

  HoldKey _k(String label, int code, {IconData? icon}) =>
      HoldKey(label: label, keyCode: code, icon: icon, dongle: dongle, mods: mods);

  @override
  Widget build(BuildContext context) {
    final layout = dongle.status.layout;
    int ch(String c) => HidKey.forChar(c, layout) ?? 0;
    ComboKey c(String label, int m, int code, {bool danger = false}) =>
        ComboKey(label: label, mods: m, keyCode: code, dongle: dongle, danger: danger);

    final keysTab = _grid([
      _k('Esc', HidKey.esc),
      _k('Tab', HidKey.tab),
      _k('Enter', HidKey.enter, icon: Icons.keyboard_return),
      _k('Bksp', HidKey.backspace, icon: Icons.backspace_outlined),
      _k('Del', HidKey.delete),
      _k('Ins', HidKey.insert),
      _k('Space', HidKey.space, icon: Icons.space_bar),
      _k('Menu', HidKey.menu),
      _k('PrtSc', HidKey.printScreen),
      _k('Caps', HidKey.capsLock),
      _k('NumLk', HidKey.numLock),
      _k('Pause/Break', HidKey.pause),
    ]);

    final fTab = _grid([for (var i = 1; i <= 12; i++) _k('F$i', HidKey.f(i))], columns: 6);

    final navTab = Row(children: [
      Expanded(
        flex: 5,
        child: _grid([
          _k('Home', HidKey.home),
          _k('PgUp', HidKey.pageUp),
          _k('End', HidKey.end),
          _k('PgDn', HidKey.pageDown),
        ], columns: 2),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 6,
        child: Column(children: [
          Row(children: [
            const Expanded(child: SizedBox()),
            Expanded(child: _k('Up', HidKey.up, icon: Icons.keyboard_arrow_up)),
            const Expanded(child: SizedBox()),
          ]),
          Row(children: [
            Expanded(child: _k('Left', HidKey.left, icon: Icons.keyboard_arrow_left)),
            Expanded(child: _k('Down', HidKey.down, icon: Icons.keyboard_arrow_down)),
            Expanded(child: _k('Right', HidKey.right, icon: Icons.keyboard_arrow_right)),
          ]),
        ]),
      ),
    ]);

    final comboTab = _grid([
      c('Ctrl+Alt+Del', Mod.ctrl | Mod.alt, HidKey.delete, danger: true),
      c('Task Mgr', Mod.ctrl | Mod.shift, HidKey.esc),
      c('Ctrl+Break', Mod.ctrl, HidKey.pause),
      c('Alt+Tab', Mod.alt, HidKey.tab),
      c('Alt+F4', Mod.alt, HidKey.f(4)),
      c('Win+R', Mod.gui, ch('r')),
      c('Win+E', Mod.gui, ch('e')),
      c('Win+D', Mod.gui, ch('d')),
      c('Win+L', Mod.gui, ch('l')),
      c('Win+X', Mod.gui, ch('x')),
      c('Win key', Mod.gui, 0), // tap the Windows key itself
      c('Ctrl+A', Mod.ctrl, ch('a')),
      c('Ctrl+C', Mod.ctrl, ch('c')),
      c('Ctrl+V', Mod.ctrl, ch('v')),
      c('Ctrl+X', Mod.ctrl, ch('x')),
      c('Ctrl+Z', Mod.ctrl, ch('z')),
      c('Ctrl+S', Mod.ctrl, ch('s')),
    ]);

    Widget media(IconData icon, int usage) => Padding(
          padding: const EdgeInsets.all(2.5),
          child: IconButton.filledTonal(
            onPressed: () {
              HapticFeedback.selectionClick();
              dongle.sendConsumer(usage);
            },
            icon: Icon(icon),
          ),
        );
    final mediaTab = Center(
      child: Wrap(alignment: WrapAlignment.center, children: [
        media(Icons.volume_down, Media.volDown),
        media(Icons.volume_off, Media.mute),
        media(Icons.volume_up, Media.volUp),
        media(Icons.skip_previous, Media.prev),
        media(Icons.play_arrow, Media.playPause),
        media(Icons.skip_next, Media.next),
      ]),
    );

    return DefaultTabController(
      length: 5,
      child: Column(children: [
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: EdgeInsets.symmetric(horizontal: 12),
          tabs: [
            Tab(text: 'Keys', height: 32),
            Tab(text: 'F1–F12', height: 32),
            Tab(text: 'Arrows', height: 32),
            Tab(text: 'Shortcuts', height: 32),
            Tab(text: 'Media', height: 32),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            children: [keysTab, fTab, navTab, comboTab, mediaTab],
          ),
        ),
      ]),
    );
  }
}
