import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two sentences a widget says before the app has said anything, and its
/// name and what it is for, are the only words the native side writes
/// itself. There is one copy in Swift and one in Android's resources, and a
/// copy that drifts is a widget that says another thing on the other phone:
/// this holds them word for word.
const _swiftPath = 'ios/CupolaWidgets/OutsideWords.swift';
const _androidPath = 'android/app/src/main/res/values/outside_words.xml';

/// `comingUpName` as `outside_coming_up_name`.
String _resourceName(String swiftName) =>
    'outside_${swiftName.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')}';

/// What the Swift file says, by the name Android gives it.
Map<String, String> _swiftWords() {
  final source = File(_swiftPath).readAsStringSync();
  return {
    for (final match in RegExp(
      r'static let (\w+) = "([^"]*)"',
    ).allMatches(source))
      _resourceName(match.group(1)!): match.group(2)!,
  };
}

Map<String, String> _androidWords() {
  final source = File(_androidPath).readAsStringSync();
  return {
    for (final match in RegExp(
      r'<string name="(\w+)"[^>]*>([^<]*)</string>',
    ).allMatches(source))
      match.group(1)!: match.group(2)!,
  };
}

void main() {
  test('the widgets say the same words on Android as on iOS', () {
    final swift = _swiftWords();
    final android = _androidWords();
    expect(swift, isNotEmpty, reason: 'no word found in $_swiftPath');
    expect(
      android,
      swift,
      reason:
          '$_androidPath and $_swiftPath must say the same words, under the '
          'same names. Change both.',
    );
  });

  test('no em dash and no "film" in the words', () {
    for (final word in _androidWords().values) {
      expect(word, isNot(contains(String.fromCharCode(0x2014))));
      expect(word.toLowerCase(), isNot(contains('film')));
    }
  });
}
