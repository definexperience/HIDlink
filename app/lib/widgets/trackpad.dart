import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dongle.dart';
import '../settings.dart';

/// Touchpad surface.
///  - 1 finger move: pointer      - tap: left click
///  - 2 finger move: scroll       - 2 finger tap: right click
///  - 3 finger tap: middle click  - tap, then touch again and move: drag
class Trackpad extends StatefulWidget {
  final Dongle dongle;
  final Settings settings;
  const Trackpad({super.key, required this.dongle, required this.settings});

  @override
  State<Trackpad> createState() => _TrackpadState();
}

class _TrackpadState extends State<Trackpad> {
  static const _tapMaxMs = 220;
  static const _tapMaxMove = 10.0;
  static const _dragWindowMs = 260;
  static const _scrollStep = 14.0; // px of finger travel per wheel notch

  final Map<int, Offset> _pts = {};
  int _maxPointers = 0;
  double _moved = 0;
  DateTime _start = DateTime.now();
  DateTime _lastTapUp = DateTime.fromMillisecondsSinceEpoch(0);
  bool _dragging = false;

  Dongle get d => widget.dongle;
  Settings get s => widget.settings;

  void _down(PointerDownEvent e) {
    _pts[e.pointer] = e.localPosition;
    if (_pts.length == 1) {
      _start = DateTime.now();
      _maxPointers = 1;
      _moved = 0;
      final sinceTap = _start.difference(_lastTapUp).inMilliseconds;
      if (s.tapToClick && sinceTap < _dragWindowMs) {
        _dragging = true;
        d.setButtons(d.mouseButtons | 1);
      }
    } else {
      _maxPointers = math.max(_maxPointers, _pts.length);
    }
  }

  void _move(PointerMoveEvent e) {
    final prev = _pts[e.pointer];
    if (prev == null) return;
    final delta = e.localPosition - prev;
    _pts[e.pointer] = e.localPosition;
    _moved += delta.distance;

    if (_pts.length == 1) {
      var gain = s.pointerSpeed;
      if (s.acceleration) gain *= 1 + math.min(delta.distance, 40) / 9;
      d.moveMouse(delta.dx * gain, delta.dy * gain);
    } else if (_pts.length == 2) {
      // each finger reports its own move: use half of each -> average
      final dy = delta.dy / 2, dx = delta.dx / 2;
      final sign = s.naturalScroll ? 1.0 : -1.0;
      d.scroll(sign * dy / _scrollStep, -sign * dx / _scrollStep);
    }
  }

  void _up(PointerEvent e, {bool cancelled = false}) {
    _pts.remove(e.pointer);
    if (_pts.isNotEmpty) return;
    final now = DateTime.now();
    final ms = now.difference(_start).inMilliseconds;
    if (_dragging) {
      _dragging = false;
      d.setButtons(d.mouseButtons & ~1);
      _lastTapUp = DateTime.fromMillisecondsSinceEpoch(0);
      return;
    }
    if (cancelled || !s.tapToClick) return;
    if (ms <= _tapMaxMs && _moved <= _tapMaxMove * _maxPointers) {
      final button = switch (_maxPointers) { 1 => 1, 2 => 2, _ => 4 };
      d.click(button);
      HapticFeedback.selectionClick();
      _lastTapUp = _maxPointers == 1 ? now : DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: (e) => _up(e, cancelled: true),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              alignment: Alignment.center,
              child: Text(
                'Trackpad\ntap = click · 2 fingers = scroll / right-click\ntap + hold + move = drag',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // one-finger scroll strip
        SizedBox(
          width: 34,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (u) {
              final sign = s.naturalScroll ? 1.0 : -1.0;
              d.scroll(sign * u.delta.dy / _scrollStep, 0);
            },
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Icon(Icons.unfold_more, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Left / middle / right buttons you can hold (e.g. hold L and drag on the pad).
class MouseButtons extends StatelessWidget {
  final Dongle dongle;
  const MouseButtons({super.key, required this.dongle});

  Widget _btn(BuildContext context, String label, int bit, int flex) {
    final cs = Theme.of(context).colorScheme;
    final pressed = (dongle.mouseButtons & bit) != 0;
    return Expanded(
      flex: flex,
      child: Listener(
        onPointerDown: (_) {
          HapticFeedback.selectionClick();
          dongle.setButtons(dongle.mouseButtons | bit);
        },
        onPointerUp: (_) => dongle.setButtons(dongle.mouseButtons & ~bit),
        onPointerCancel: (_) => dongle.setButtons(dongle.mouseButtons & ~bit),
        child: Container(
          height: 46,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: pressed ? cs.primary.withValues(alpha: 0.35) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          alignment: Alignment.center,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _btn(context, 'Left', 1, 3),
      _btn(context, 'Mid', 4, 1),
      _btn(context, 'Right', 2, 3),
    ]);
  }
}
