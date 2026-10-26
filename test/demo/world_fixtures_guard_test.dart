import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/world/fixtures.dart';

/// The demo world lives in `lib/` so the app can serve it, and the tests
/// read the very same world. These hold the two things that move would break
/// without a compile error: a fixture the world names but the app does not
/// carry, and a test-only import reaching the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final named = _namedByTheWorld();
  final declared = _declaredInPubspec();

  test('the world names fixtures', () {
    expect(named, isNotEmpty);
  });

  test('every fixture the world names exists and ships with the app', () {
    for (final path in named) {
      expect(
        File('${WorldFixtures.directory}$path').existsSync(),
        isTrue,
        reason: path,
      );
    }
    expect(declared, named, reason: 'pubspec.yaml lists exactly these');
  });

  test('the app bundle hands every one of them to the demo', () async {
    await WorldFixtures.preload(rootBundle);
    expect(WorldFixtures.preloaded.toSet(), containsAll(named));
  });

  test('nothing under lib/ imports a test library', () {
    final testOnly = RegExp(
      r'''^\s*(import|export)\s+'(package:flutter_test/|package:test/|[^']*test/)''',
      multiLine: true,
    );
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      expect(
        testOnly.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: file.path,
      );
    }
  });
}

/// Every `<service>/<file>.json` literal in the world's sources.
Set<String> _namedByTheWorld() {
  final literal = RegExp(r"'([a-z_]+/[A-Za-z0-9_.\-]+\.json)'");
  return {
    for (final file in Directory('lib/demo/world').listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart'))
        for (final match in literal.allMatches(file.readAsStringSync()))
          match.group(1)!,
  };
}

/// Every `test/fixtures/` asset `pubspec.yaml` declares.
Set<String> _declaredInPubspec() {
  final entry = RegExp(r'^\s*-\s+test/fixtures/(\S+)$', multiLine: true);
  return {
    for (final match in entry.allMatches(
      File('pubspec.yaml').readAsStringSync(),
    ))
      match.group(1)!,
  };
}
