/// No control in `lib/` is handed an empty callback in place of the one it was
/// not given.
///
/// `AsyncValueWidget` handed its band `onRetry ?? () {}`, and the Discover rail
/// did the same: a Retry with nothing behind it, drawn in the remedy's fill,
/// that did nothing when tapped. Better no control than one that fails: a
/// widget that may not have the callback draws no control (or says the
/// failure with no verb), and one that always draws it requires it.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

void main() {
  test('no `?? () {}` stands in for a missing callback', () {
    final inert = RegExp(r'\?\?\s*\(\)\s*(?:\{\s*\}|=>\s*null\b)');
    final offenders = [
      for (final file in libCode())
        for (final match in inert.allMatches(file.code))
          '${file.path}:'
              '${'\n'.allMatches(file.code.substring(0, match.start)).length + 1}',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Require the callback, or draw no control without it: an empty '
          'one is a Retry that does nothing.',
    );
  });
}
