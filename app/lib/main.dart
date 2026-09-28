import 'package:flutter/material.dart';

import 'dongle.dart';
import 'protocol.dart';
import 'settings.dart';
import 'widgets/keys.dart';
import 'widgets/textbar.dart';
import 'widgets/trackpad.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = Settings();
  await settings.load();
  final dongle = Dongle();
  runApp(HidLinkApp(dongle: dongle, settings: settings));
  dongle.init();
}

class HidLinkApp extends StatelessWidget {
  final Dongle dongle;
  final Settings settings;
  const HidLinkApp({super.key, required this.dongle, required this.settings});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3C8CFF), brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'HIDlink',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: ListenableBuilder(
        listenable: dongle,
        builder: (context, _) => dongle.isConnected
            ? ControlScreen(dongle: dongle, settings: settings)
            : ConnectScreen(dongle: dongle),
      ),
    );
  }
}

// ============================================================================
// Connect screen
// ============================================================================
class ConnectScreen extends StatelessWidget {
  final Dongle dongle;
  const ConnectScreen({super.key, required this.dongle});

  @override
  Widget build(BuildContext context) {
    final d = dongle;
    final cs = Theme.of(context).colorScheme;
    final busy = d.state == LinkState.connecting || d.state == LinkState.securing;
    final list = d.found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

    Widget body;
    if (!d.bluetoothOn) {
      body = const _Hint(icon: Icons.bluetooth_disabled, title: 'Bluetooth is off', text: 'Turn on Bluetooth to find your dongle.');
    } else if (d.rejectedDuringSetup) {
      body = _Hint(
        icon: Icons.link_off,
        title: 'Dongle refused this phone',
        text: 'This phone is not paired with the dongle yet.\n\n'
            '1. Hold the button on the dongle for 3 seconds until the screen shows PAIRING (LED blinks blue).\n'
            '2. Tap "Try again" and accept the pairing request on your phone.\n\n'
            'Still failing after the dongle was reset? Remove "${d.deviceName ?? 'HIDlink'}" '
            'from your phone\'s Bluetooth settings and try again.',
        action: FilledButton(onPressed: d.retryAfterRejection, child: const Text('Try again')),
      );
    } else if (busy) {
      body = _Hint(
        icon: Icons.bluetooth_searching,
        title: d.state == LinkState.connecting ? 'Connecting…' : 'Securing connection…',
        text: d.state == LinkState.securing
            ? 'First time? Accept the pairing request on your phone.'
            : 'Connecting to ${d.deviceName ?? 'dongle'}',
        progress: true,
      );
    } else if (list.isEmpty) {
      body = _Hint(
        icon: Icons.usb,
        title: d.state == LinkState.scanning ? 'Looking for dongles…' : 'No dongle found',
        text: 'Plug the HIDlink dongle into the PC. It shows up here within a few seconds.',
        progress: d.state == LinkState.scanning,
        action: d.state == LinkState.scanning ? null : FilledButton(onPressed: d.startScan, child: const Text('Search again')),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final f in list)
            Card(
              child: ListTile(
                leading: const Icon(Icons.keyboard_alt_outlined),
                title: Text(f.name),
                subtitle: Text(f.id == d.lastDeviceId ? 'Last used · ${f.rssi} dBm' : 'Signal ${f.rssi} dBm'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => d.connect(f.id, f.name),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'New dongles accept a phone automatically the first time. To add another phone, '
            'hold the dongle button for 3 s first.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('HIDlink'),
        actions: [
          if (d.state != LinkState.scanning && !busy)
            IconButton(onPressed: d.startScan, icon: const Icon(Icons.refresh), tooltip: 'Search again'),
        ],
      ),
      body: Column(children: [
        if (d.error != null)
          MaterialBanner(
            content: Text(d.error!),
            actions: [TextButton(onPressed: () => d.startScan(), child: const Text('Retry'))],
          ),
        Expanded(child: body),
      ]),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final bool progress;
  final Widget? action;
  const _Hint({required this.icon, required this.title, required this.text, this.progress = false, this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: cs.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          if (progress) ...[const SizedBox(height: 20), const CircularProgressIndicator()],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

// ============================================================================
// Control screen
// ============================================================================
class ControlScreen extends StatefulWidget {
  final Dongle dongle;
  final Settings settings;
  const ControlScreen({super.key, required this.dongle, required this.settings});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final mods = Modifiers();
  bool showKeys = true;

  Dongle get d => widget.dongle;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([d, widget.settings, mods]),
      builder: (context, _) {
        final st = d.status;
        final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 12,
            title: Text(d.deviceName ?? 'HIDlink', style: const TextStyle(fontSize: 17)),
            actions: [
              IconButton(
                tooltip: showKeys ? 'Hide keys' : 'Show keys',
                icon: Icon(showKeys ? Icons.keyboard_hide_outlined : Icons.apps),
                onPressed: () => setState(() => showKeys = !showKeys),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'settings':
                      _openSettings(context);
                    case 'release':
                      mods.clear();
                      d.releaseAll();
                    case 'disconnect':
                      d.disconnect();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'settings', child: Text('Settings')),
                  PopupMenuItem(value: 'release', child: Text('Release all keys')),
                  PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(children: [
                _StatusStrip(status: st, onLayoutTap: () => _pickLayout(context)),
                const SizedBox(height: 6),
                Expanded(child: Trackpad(dongle: d, settings: widget.settings)),
                const SizedBox(height: 6),
                MouseButtons(dongle: d),
                if (showKeys && !keyboardOpen) ...[
                  const SizedBox(height: 6),
                  ModifierBar(mods: mods),
                  SizedBox(height: 170, child: KeyPanel(dongle: d, mods: mods)),
                ] else if (keyboardOpen) ...[
                  const SizedBox(height: 4),
                  ModifierBar(mods: mods),
                ],
                const SizedBox(height: 6),
                TextBar(key: const ValueKey('textbar'), dongle: d, settings: widget.settings, mods: mods),
              ]),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickLayout(BuildContext context) async {
    final id = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('PC keyboard layout'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Choose the layout the PC is set to, so typed text comes out right. '
                'Saved on the dongle.', style: TextStyle(fontSize: 13)),
          ),
          for (var i = 0; i < Layouts.names.length; i++)
            ListTile(
              title: Text(Layouts.names[i]),
              trailing: i == d.status.layout ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, i),
            ),
        ],
      ),
    );
    if (id != null) await d.setLayout(id);
  }

  void _openSettings(BuildContext context) {
    final s = widget.settings;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: Listenable.merge([s, d]),
        builder: (ctx, _) => ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 24), children: [
          ListTile(
            title: const Text('Pointer speed'),
            subtitle: Slider(
              min: 0.4,
              max: 4,
              divisions: 36,
              value: s.pointerSpeed,
              label: s.pointerSpeed.toStringAsFixed(1),
              onChanged: (v) => s.update(pointerSpeed: v),
            ),
          ),
          SwitchListTile(
            title: const Text('Pointer acceleration'),
            value: s.acceleration,
            onChanged: (v) => s.update(acceleration: v),
          ),
          SwitchListTile(
            title: const Text('Natural scrolling'),
            subtitle: const Text('Content follows your fingers'),
            value: s.naturalScroll,
            onChanged: (v) => s.update(naturalScroll: v),
          ),
          SwitchListTile(
            title: const Text('Tap to click'),
            value: s.tapToClick,
            onChanged: (v) => s.update(tapToClick: v),
          ),
          ListTile(
            title: const Text('PC keyboard layout'),
            subtitle: Text(Layouts.names[d.status.layout.clamp(0, Layouts.names.length - 1).toInt()]),
            onTap: () {
              Navigator.pop(ctx);
              _pickLayout(context);
            },
          ),
          ListTile(
            title: const Text('PC operating system'),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('How accents, € etc. are typed when the layout has no key for them'),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (var i = 0; i < OsModes.names.length; i++)
                    ButtonSegment(value: i, label: Text(OsModes.names[i])),
                ],
                selected: {d.status.osMode.clamp(0, OsModes.names.length - 1).toInt()},
                onSelectionChanged: (v) => d.setOsMode(v.first),
              ),
            ]),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text('Forget this dongle'),
            subtitle: const Text('Stop auto-connecting and remove the pairing from this phone'),
            onTap: () {
              Navigator.pop(ctx);
              d.forgetDongle(removePhonePairing: true);
            },
          ),
        ]),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  final DongleStatus status;
  final VoidCallback onLayoutTap;
  const _StatusStrip({required this.status, required this.onLayoutTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(String text, Color color, {IconData? icon}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
            Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ]),
        );

    final pc = !status.pcConnected
        ? chip('No PC', cs.error, icon: Icons.usb_off)
        : status.biosMode
            ? chip('BIOS mode (no mouse)', Colors.orange, icon: Icons.memory)
            : chip('PC connected', Colors.green, icon: Icons.usb);

    return SizedBox(
      height: 28,
      child: Row(children: [
        pc,
        if (status.capsLock) chip('CAPS', Colors.orange),
        if (status.numLock) chip('NUM', cs.primary),
        const Spacer(),
        InkWell(
          onTap: onLayoutTap,
          borderRadius: BorderRadius.circular(20),
          child: chip(
            Layouts.names[status.layout.clamp(0, Layouts.names.length - 1).toInt()].split(' ').first,
            cs.primary,
            icon: Icons.language,
          ),
        ),
      ]),
    );
  }
}
