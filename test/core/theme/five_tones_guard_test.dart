/// A status reads one of five arms: green, amber, red, blue, neutral.
///
/// `StatusTone.primary` was a sixth: "Not requested" (Seerr's "Available to
/// request") wore the ink as a call to action, an administrator's row in
/// Jellyfin wore it as a role, and an In flight percentage borrowed the tone
/// helper to paint the ink. None of them is a state the tone rule has an arm
/// for. The arm stays in the enum only for a design-catalog scene that still
/// names it; nothing in the app may resolve a status to it.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

/// The exhaustive switches over [StatusTone] that have to name every arm while
/// the enum carries it, and resolve it to nothing a status uses.
const _switches = {
  'lib/core/widgets/status_badge.dart',
  'lib/features/services/domain/kpi_aggregate.dart',
};

void main() {
  test('no status resolves to StatusTone.primary', () {
    final offenders = [
      for (final file in libCode())
        if (!_switches.contains(file.path))
          for (final match in RegExp(
            r'\bStatusTone\.primary\b',
          ).allMatches(file.code))
            '${file.path}:'
                '${'\n'.allMatches(file.code.substring(0, match.start)).length + 1}',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'A status takes one of the five arms (success, warning, error, '
          'info, neutral); the ink is not one of them.',
    );
  });
}
