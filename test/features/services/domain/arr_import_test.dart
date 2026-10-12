/// Which history events the two regions that read history care about.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/arr_import.dart';

void main() {
  test('each arr names the same act after its own unit', () {
    for (final event in const [
      'downloadFolderImported',
      'seriesFolderImported',
      'trackFileImported',
      'bookFileImported',
    ]) {
      expect(classifyHistoryEvent(event), ArrImportOutcome.imported);
    }
  });

  test('a failed grab and a failed import are both failures', () {
    expect(classifyHistoryEvent('downloadFailed'), ArrImportOutcome.failed);
    expect(classifyHistoryEvent('importFailed'), ArrImportOutcome.failed);
  });

  test('a download stopped on purpose is not a fault', () {
    // The tone rule's fourth arm: ignoring a download is a decision the user
    // already made, so it is neither an import nor a failure.
    expect(classifyHistoryEvent('downloadIgnored'), ArrImportOutcome.other);
  });

  test('everything else is other: never guessed into the rail', () {
    expect(classifyHistoryEvent('grabbed'), ArrImportOutcome.other);
    expect(classifyHistoryEvent('movieFileRenamed'), ArrImportOutcome.other);
    // A future \*arr inventing an event must not silently become an import in a
    // region whose whole claim is "this is what landed".
    expect(classifyHistoryEvent('somethingNew'), ArrImportOutcome.other);
    expect(classifyHistoryEvent(null), ArrImportOutcome.other);
    expect(classifyHistoryEvent('  '), ArrImportOutcome.other);
  });

  group('parseAddedTimestamp', () {
    test('parses the ISO 8601 string the arr APIs return', () {
      expect(
        parseAddedTimestamp('2024-03-14T09:26:53Z'),
        DateTime.utc(2024, 3, 14, 9, 26, 53),
      );
    });

    test('returns null for absent, blank or unparseable values', () {
      // Null rather than the epoch: a bad timestamp must not sort an item to
      // the top of a "newest first" list, and must not take it down either.
      expect(parseAddedTimestamp(null), isNull);
      expect(parseAddedTimestamp(''), isNull);
      expect(parseAddedTimestamp('   '), isNull);
      expect(parseAddedTimestamp('not a date'), isNull);
    });
  });
}
