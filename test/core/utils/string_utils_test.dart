import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/string_utils.dart';

void main() {
  group('formatRuntimeMinutes', () {
    test('speaks hours and minutes', () {
      // Radarr shipped `127 min`, Seerr `173min`.
      expect(formatRuntimeMinutes(127), '2\u00A0h 7\u00A0min');
      expect(formatRuntimeMinutes(173), '2\u00A0h 53\u00A0min');
    });

    test('drops the hour under an hour', () {
      expect(formatRuntimeMinutes(47), '47\u00A0min');
      expect(formatRuntimeMinutes(1), '1\u00A0min');
    });

    test('drops the minutes on a whole hour', () {
      expect(formatRuntimeMinutes(120), '2\u00A0h');
      expect(formatRuntimeMinutes(60), '1\u00A0h');
    });

    test('reports nothing for a runtime the service does not have', () {
      // Zero is a missing fact, not a film of no length, and an empty string is
      // dropped by both the metadata line and the fact grid.
      expect(formatRuntimeMinutes(0), '');
      expect(formatRuntimeMinutes(-5), '');
    });
  });

  group('truncateTitle', () {
    test('leaves a title that fits alone', () {
      expect(truncateTitle('Inception'), 'Inception');
    });

    test('trims surrounding whitespace', () {
      expect(truncateTitle('  Inception  '), 'Inception');
    });

    test('caps a title that would grow a dialog past its own buttons', () {
      final long = 'A ${'very ' * 60}long title';
      final result = truncateTitle(long);

      expect(result.length, lessThanOrEqualTo(65));
      expect(result, endsWith('…'));
      // An ellipsis glyph, not three periods, which read as a pause.
      expect(result, isNot(contains('...')));
    });

    test('cuts on a word boundary rather than mid-word', () {
      final result = truncateTitle(
        'The Lord of the Rings The Fellowship of the Ring Extended Edition '
        'Remastered',
        maxChars: 40,
      );

      expect(result, 'The Lord of the Rings The Fellowship of…');
      expect(result.length, lessThanOrEqualTo(41));
    });

    test('hard-cuts a single word longer than the budget', () {
      // A word boundary is only honoured in the last third, so a title with no
      // early space cannot collapse to a lone ellipsis.
      final result = truncateTitle('A${'b' * 200}', maxChars: 20);

      expect(result.length, 21);
      expect(result, endsWith('…'));
    });

    test('is stable at exactly the budget', () {
      final exact = 'x' * 64;
      expect(truncateTitle(exact), exact);
      // One character over: 64 kept plus the ellipsis glyph.
      expect(truncateTitle('${exact}y').length, 65);
    });
  });
}
