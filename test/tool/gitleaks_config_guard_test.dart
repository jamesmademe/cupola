import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A gitleaks config replaces the built-in rules unless it extends them, and
/// an allowlist on its own scans with no rule at all: the CI job would pass on
/// every secret. This holds the one line that keeps the scan real.
void main() {
  test('the tracked gitleaks config extends the default rules', () {
    final config = File('.gitleaks.toml').readAsStringSync();

    expect(
      RegExp(
        r'^\[extend\]\s*\nuseDefault\s*=\s*true',
        multiLine: true,
      ).hasMatch(config),
      isTrue,
    );
  });
}
