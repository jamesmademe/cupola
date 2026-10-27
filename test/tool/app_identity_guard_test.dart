import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The same bundle id on one machine shares preferences, keychain and App
/// Group (AGENTS.md, App identities). Production holds real connections, the
/// testlab its seed, dev nothing: these hold that a release always builds
/// production and that the dev script can only build dev.
void main() {
  const production = 'group.com.matthwlabs.cupola';
  const isolated = ['.dev', '.testlab'];

  group('a release builds the production identity', () {
    test(
      'the iOS configurations carry no suffix and the house entitlements',
      () {
        for (final path in [
          'ios/Flutter/Debug.xcconfig',
          'ios/Flutter/Release.xcconfig',
        ]) {
          final settings = _xcconfig(path);
          expect(settings['CUPOLA_BUNDLE_SUFFIX'], '', reason: path);
          expect(settings['CUPOLA_APP_GROUP'], production, reason: path);
          expect(
            settings['CUPOLA_ENTITLEMENTS'],
            'Runner/Runner.entitlements',
            reason: path,
          );
        }
        final widgets = _xcconfig('ios/CupolaWidgets/CupolaWidgets.xcconfig');
        expect(widgets['CUPOLA_BUNDLE_SUFFIX'], '');
        expect(widgets['CUPOLA_APP_GROUP'], production);
      },
    );

    test(
      'the macOS configurations carry no suffix and the house entitlements',
      () {
        for (final path in [
          'macos/Runner/Configs/Debug.xcconfig',
          'macos/Runner/Configs/Release.xcconfig',
          'macos/Runner/Configs/AppInfo.xcconfig',
        ]) {
          expect(_xcconfig(path)['CUPOLA_BUNDLE_SUFFIX'], '', reason: path);
        }
        final appInfo = _xcconfig('macos/Runner/Configs/AppInfo.xcconfig');
        expect(
          appInfo['CUPOLA_ENTITLEMENTS[config=Release]'],
          'Runner/Release.entitlements',
        );
      },
    );

    test('no production entitlement or export option names an isolated id', () {
      for (final path in [
        'ios/Runner/Runner.entitlements',
        'ios/CupolaWidgets/CupolaWidgets.entitlements',
        'macos/Runner/Release.entitlements',
        'macos/Runner/DebugProfile.entitlements',
        'ios/ExportOptions-testflight.plist',
        'macos/ExportOptions.plist',
        'macos/ExportOptions-testflight.plist',
      ]) {
        final text = File(path).readAsStringSync();
        for (final suffix in isolated) {
          expect(
            text.contains('com.matthwlabs.cupola$suffix'),
            isFalse,
            reason: '$path names $suffix',
          );
        }
      }
    });

    test('release.sh refuses to run with an identity override set', () {
      final script = File('scripts/release.sh').readAsStringSync();
      expect(
        script.contains("if env | grep -q '^FLUTTER_XCODE_'; then"),
        isTrue,
      );
      expect(script.contains('CUPOLA_TESTLAB_KEYCHAIN'), isFalse);
      expect(script.contains('run_dev.sh'), isTrue);
    });
  });

  group('run_dev.sh builds the dev identity alone', () {
    final script = File('scripts/run_dev.sh').readAsStringSync();

    String value(String name) => RegExp(
      '^$name="([^"]*)"',
      multiLine: true,
    ).firstMatch(script)!.group(1)!;

    test('it sets the dev suffix, App Group and keychain', () {
      expect(value('DEV_SUFFIX'), '.dev');
      expect(value('DEV_APP_GROUP'), 'group.com.matthwlabs.cupola.dev');
      expect(value('DEV_KEYCHAIN'), 'com.matthwlabs.cupola.dev');
      for (final setting in [
        'FLUTTER_XCODE_CUPOLA_BUNDLE_SUFFIX="\$DEV_SUFFIX"',
        'FLUTTER_XCODE_CUPOLA_APP_GROUP="\$DEV_APP_GROUP"',
        'FLUTTER_XCODE_CUPOLA_ENTITLEMENTS="\$ENTITLEMENTS"',
        'CUPOLA_TESTLAB_KEYCHAIN_SERVICE=\$DEV_KEYCHAIN',
      ]) {
        expect(script.contains(setting), isTrue, reason: setting);
      }
    });

    test('its entitlements exist and name the dev group alone', () {
      final ios = File('ios/Runner/RunnerDev.entitlements').readAsStringSync();
      expect(
        ios.contains('<string>group.com.matthwlabs.cupola.dev</string>'),
        isTrue,
      );
      expect(
        ios.contains('<string>com.matthwlabs.cupola.dev</string>'),
        isTrue,
      );
      expect(ios.contains('<string>$production</string>'), isFalse);
      final macos = File('macos/Runner/Dev.entitlements').readAsStringSync();
      expect(macos.contains('<key>'), isFalse);
      expect(
        script.contains('ENTITLEMENTS="Runner/RunnerDev.entitlements"'),
        isTrue,
      );
      expect(script.contains('ENTITLEMENTS="Runner/Dev.entitlements"'), isTrue);
    });

    test('it refuses the simulator holding the real connections', () {
      expect(value('HOUSE_SIMULATOR'), '3275916D-565E-4B49-89A3-D87227209A7F');
      expect(script.contains('"\$DEVICE" == "\$HOUSE_SIMULATOR"'), isTrue);
      expect(script.contains('flutter install'), isFalse);
    });
  });
}

/// The last value each key takes in an xcconfig, as Xcode reads it.
Map<String, String> _xcconfig(String path) {
  final settings = <String, String>{};
  final line = RegExp(r'^([A-Z_]+(?:\[[^\]]+\])?)\s*=\s*(.*?)\s*$');
  for (final raw in File(path).readAsLinesSync()) {
    final match = line.firstMatch(raw);
    if (match != null) settings[match.group(1)!] = match.group(2)!;
  }
  return settings;
}
