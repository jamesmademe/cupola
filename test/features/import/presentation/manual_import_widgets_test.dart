import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/features/import/presentation/manual_import_widgets.dart';

void main() {
  group('formatImportBytes', () {
    test('keeps the "no size reported" sentinel', () {
      expect(formatImportBytes(0), 'Unknown size');
      expect(formatImportBytes(-1), 'Unknown size');
    });

    test('renders every rung through the shared precise ladder', () {
      // The point of the test is the agreement, not the strings: manual import
      // used to carry its own ladder (`unit <= 1 ? 0 : 1` decimals, no rung
      // above TB), so a file that read "5.0 GB" while being imported read
      // "5.00 GB" in the qBittorrent list it landed in.
      for (final size in const [
        512,
        1024,
        1023 * 1024,
        5 * 1024 * 1024,
        5 * 1024 * 1024 * 1024,
        2199023255552,
      ]) {
        expect(formatImportBytes(size), formatBytesPrecise(size));
      }

      expect(formatImportBytes(512), '512 B');
      expect(formatImportBytes(5 * 1024 * 1024 * 1024), '5.00 GB');
      expect(formatImportBytes(2199023255552), '2.00 TB');
    });
  });

  group('manualImportSelectionSummary', () {
    String summary({
      int selected = 3,
      int selectable = 5,
      int reimports = 0,
      int needingIdentity = 0,
      int selectedBytes = 0,
    }) {
      return manualImportSelectionSummary(
        selected: selected,
        selectable: selectable,
        reimports: reimports,
        needingIdentity: needingIdentity,
        selectedBytes: selectedBytes,
      );
    }

    test('names the whole selection against what could be selected', () {
      expect(
        summary(selected: 3, selectable: 5, needingIdentity: 1),
        startsWith('3 of 5 selected'),
      );
    });

    test('a figure of zero is dropped, never printed as a zero', () {
      // "0 re-imports · 0 need an identity" is three facts about nothing, and
      // it is the line the user reads on every ordinary scan.
      final line = summary(selected: 0, selectable: 5);
      expect(line, '0 of 5 selected');
    });

    test('each optional segment appears exactly when its figure is real', () {
      final line = summary(
        selected: 4,
        selectable: 7,
        reimports: 1,
        needingIdentity: 1,
        selectedBytes: 1024,
      );
      expect(line.split(' \u00b7 '), [
        '4 of 7 selected',
        '1 re-import',
        '1 needs an identity',
        '1.00 KB',
      ]);
    });

    test('the plural follows the figure on both counts', () {
      final line = summary(reimports: 2, needingIdentity: 2);
      expect(line, contains('2 re-imports'));
      expect(line, contains('2 need an identity'));
    });

    test('a selection whose sizes nobody reported is not zero bytes', () {
      // The sentinel rather than "0 B": a count the service never answered is
      // not an empty one, and "0 B" would say the import moves nothing.
      expect(summary(selected: 2, selectedBytes: 0), contains('Unknown size'));
    });

    test('nothing selected carries no size at all', () {
      expect(summary(selected: 0, selectedBytes: 0), isNot(contains('size')));
    });
  });
}
