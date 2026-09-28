import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dongle.dart';
import '../protocol.dart';
import '../settings.dart';
import 'keys.dart';

/// Text input. Two modes:
///  - Send: type/paste text, then press "Type" (or "Type ⏎" to add Enter).
///  - Live: every keystroke on the phone keyboard goes to the PC directly.
class TextBar extends StatefulWidget {
  final Dongle dongle;
  final Settings settings;
  final Modifiers mods;
  const TextBar({super.key, required this.dongle, required this.settings, required this.mods});

  @override
  State<TextBar> createState() => _TextBarState();
}

class _TextBarState extends State<TextBar> {
  // In live mode the field always holds this invisible sentinel, so a
  // backspace on an "empty" field is still detected.
  static const _sentinel = '​';

  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String _last = '';
  Future<void> _queue = Future.value();

  bool get _live => widget.settings.liveTyping;

  @override
  void initState() {
    super.initState();
    _resetField();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _resetField() {
    final t = _live ? _sentinel : '';
    _ctrl.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    _last = t;
  }

  void _enqueue(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).catchError((_) {});
  }

  // ---- live mode ----------------------------------------------------------
  void _onChanged(String now) {
    if (!_live) {
      setState(() {}); // update send button state
      return;
    }
    final before = _last;
    var p = 0;
    while (p < before.length && p < now.length && before.codeUnitAt(p) == now.codeUnitAt(p)) {
      p++;
    }
    final removed = before.length - p;
    final added = now.substring(p).replaceAll(_sentinel, '');
    final d = widget.dongle;

    if (removed > 0) {
      _enqueue(() async {
        for (var i = 0; i < removed; i++) {
          await d.tap(0, HidKey.backspace);
        }
      });
    }
    if (added.isNotEmpty) {
      final m = widget.mods.consume();
      final key = added.length == 1 ? HidKey.forChar(added, d.status.layout) : null;
      if (m != 0 && key != null) {
        _enqueue(() => d.tap(m, key)); // e.g. Ctrl + c typed on the phone keyboard
      } else {
        _enqueue(() async => _warnSkipped(await d.typeText(added, showProgress: false)));
      }
    }

    // Always go back to just the (invisible) sentinel: nothing collects in
    // the field, and the next backspace is still detected.
    _resetField();
  }

  void _onSubmitted(String _) {
    if (_live) {
      _enqueue(() => widget.dongle.tap(widget.mods.consume(), HidKey.enter));
      _resetField();
      _focus.requestFocus();
    } else {
      _send(enter: false);
    }
  }

  // ---- send mode ----------------------------------------------------------
  Future<void> _send({required bool enter}) async {
    final text = _ctrl.text;
    if (text.isEmpty && !enter) return;
    _ctrl.clear();
    setState(() {});
    final skipped = await widget.dongle.typeText(text);
    if (enter) await widget.dongle.tap(0, HidKey.enter);
    _warnSkipped(skipped);
  }

  void _warnSkipped(int skipped) {
    if (skipped == 0 || !mounted) return;
    final bios = widget.dongle.status.biosMode;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(bios
          ? '$skipped character(s) skipped: in BIOS mode only plain keyboard characters can be typed.'
          : '$skipped character(s) skipped: they can\'t be typed on the PC (e.g. emoji on Windows).'),
    ));
  }

  // ---- paste as keystrokes ----------------------------------------------
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    // A copied password often carries a trailing line break; don't press Enter for it.
    final text = (data?.text ?? '').replaceFirst(RegExp(r'[\r\n]+$'), '');
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
      return;
    }
    final skipped = await widget.dongle.typeText(text);
    if (!mounted) return;
    if (skipped > 0) {
      _warnSkipped(skipped);
    } else {
      // never show the text itself: it's often a password
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('Typed ${text.runes.length} characters from the clipboard'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dongle;
    final cs = Theme.of(context).colorScheme;
    final typing = d.typingProgress >= 0;

    // The text field must stay the SAME widget in the tree at all times:
    // if Flutter rebuilds it (e.g. because a row is inserted above it), the
    // phone keyboard closes. Hence the keys and the fixed structure below.
    final field = TextField(
      controller: _ctrl,
      focusNode: _focus,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      textInputAction: TextInputAction.send,
      onEditingComplete: () {}, // keep the keyboard open after Enter
      keyboardType: TextInputType.visiblePassword, // no autocorrect/predictions
      onChanged: _onChanged,
      onSubmitted: _onSubmitted,
      showCursor: !_live,
      enableInteractiveSelection: !_live,
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'Text to type on the PC',
        border: OutlineInputBorder(),
      ),
    );

    return Column(mainAxisSize: MainAxisSize.min, children: [
      // progress only for "Type"/"Paste" of longer text, never in live mode
      SizedBox(
        key: const ValueKey('progress'),
        height: typing && !_live ? 36 : 0,
        child: typing && !_live
            ? Row(children: [
                Expanded(child: LinearProgressIndicator(value: d.typingProgress)),
                TextButton(onPressed: d.cancelTyping, child: const Text('Stop')),
              ])
            : null,
      ),
      Row(key: const ValueKey('input'), children: [
        IconButton(
          tooltip: _live ? 'Live typing (on)' : 'Live typing (off)',
          isSelected: _live,
          icon: const Icon(Icons.keyboard_outlined),
          selectedIcon: const Icon(Icons.keyboard),
          onPressed: () {
            widget.settings.update(liveTyping: !_live);
            _resetField();
            setState(() {});
            if (_live) {
              _focus.requestFocus();
              SystemChannels.textInput.invokeMethod('TextInput.show');
            }
          },
        ),
        Expanded(
          child: Stack(alignment: Alignment.center, children: [
            // In live mode the field is invisible: it only catches the
            // keystrokes; nothing you type is shown in the app.
            Opacity(opacity: _live ? 0 : 1, child: field),
            if (_live)
              Positioned.fill(
                child: IgnorePointer(
                  // taps fall through to the invisible field -> keyboard opens
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cs.primary),
                    ),
                    child: Text(
                      _focus.hasFocus ? 'Live typing → PC' : 'Tap here to type live',
                      style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        if (!_live) ...[
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Type',
            onPressed: typing || _ctrl.text.isEmpty ? null : () => _send(enter: false),
            icon: const Icon(Icons.send),
          ),
          IconButton.filledTonal(
            tooltip: 'Type + Enter',
            onPressed: typing ? null : () => _send(enter: true),
            icon: const Icon(Icons.keyboard_return),
          ),
        ],
        const SizedBox(width: 4),
        IconButton.filled(
          tooltip: 'Paste as keystrokes',
          onPressed: typing ? null : _paste,
          style: IconButton.styleFrom(
            backgroundColor: cs.tertiary,
            foregroundColor: cs.onTertiary,
          ),
          icon: const Icon(Icons.content_paste_go),
        ),
      ]),
    ]);
  }
}
