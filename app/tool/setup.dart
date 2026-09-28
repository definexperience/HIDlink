// One-time project setup, run from the app folder AFTER `flutter create`:
//
//   flutter create --org nl.example --project-name hidlink --platforms=android,ios .
//   dart run tool/setup.dart
//
// It adds the Bluetooth permissions to the generated Android/iOS projects
// and sets the app name. Safe to run more than once.
import 'dart:io';

void main() {
  var ok = true;
  ok &= _android();
  ok &= _ios();
  // `flutter create` adds a counter-app test that doesn't match this app
  final test = File('test/widget_test.dart');
  if (test.existsSync() && test.readAsStringSync().contains('MyApp')) {
    test.deleteSync();
    stdout.writeln('✓ removed template test/widget_test.dart');
  }
  stdout.writeln(ok ? '\nSetup done.' : '\nSetup finished with warnings (see above).');
}

bool _android() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) {
    stderr.writeln('! $f not found – run `flutter create` first (see README).');
    return false;
  }
  var xml = f.readAsStringSync();

  const perms = '''
    <!-- HIDlink: Bluetooth LE -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
''';
  if (!xml.contains('BLUETOOTH_CONNECT')) {
    final i = xml.indexOf('<application');
    if (i < 0) {
      stderr.writeln('! Could not find <application> in $f');
      return false;
    }
    xml = xml.substring(0, i) + perms.trimLeft() + '\n    ' + xml.substring(i);
  }
  xml = xml.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="HIDlink"');
  // keep the screen layout stable when the phone keyboard opens
  if (!xml.contains('android:windowSoftInputMode')) {
    xml = xml.replaceFirst('android:name=".MainActivity"',
        'android:name=".MainActivity"\n            android:windowSoftInputMode="adjustResize"');
  }
  f.writeAsStringSync(xml);
  stdout.writeln('✓ Android manifest updated');
  return true;
}

bool _ios() {
  final plist = File('ios/Runner/Info.plist');
  if (!plist.existsSync()) {
    stdout.writeln('- iOS project not found, skipped (fine for Android-only).');
    return true;
  }
  var s = plist.readAsStringSync();
  if (!s.contains('NSBluetoothAlwaysUsageDescription')) {
    const keys = '''
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>HIDlink uses Bluetooth to connect to your USB keyboard/mouse dongle.</string>
	<key>NSBluetoothPeripheralUsageDescription</key>
	<string>HIDlink uses Bluetooth to connect to your USB keyboard/mouse dongle.</string>
''';
    final i = s.lastIndexOf('</dict>');
    s = s.substring(0, i) + keys + s.substring(i);
  }
  s = s.replaceFirstMapped(
      RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'), (m) => '${m[1]}HIDlink${m[2]}');
  plist.writeAsStringSync(s);
  stdout.writeln('✓ iOS Info.plist updated');

  // universal_ble needs iOS 13.1+
  final pbx = File('ios/Runner.xcodeproj/project.pbxproj');
  if (pbx.existsSync()) {
    final t = pbx.readAsStringSync().replaceAllMapped(
        RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = (\d+)\.(\d+);'),
        (m) => (int.parse(m[1]!) < 13 || (m[1] == '13' && m[2] == '0')) ? 'IPHONEOS_DEPLOYMENT_TARGET = 13.1;' : m[0]!);
    pbx.writeAsStringSync(t);
  }
  final podfile = File('ios/Podfile');
  if (podfile.existsSync()) {
    podfile.writeAsStringSync(podfile
        .readAsStringSync()
        .replaceFirst(RegExp(r"^#?\s*platform :ios, '[\d.]+'", multiLine: true), "platform :ios, '13.1'"));
  }
  stdout.writeln('✓ iOS deployment target 13.1');
  return true;
}
