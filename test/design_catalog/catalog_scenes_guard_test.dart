import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/code_scan.dart';
import 'catalog.dart';

/// **Every documented widget is drawn at twice the reading size at least once.**
///
/// The catalog drew almost only the resting state, which is how a selected
/// filter chip could paint its label in the colour of its own fill, in both
/// themes, across the whole app, with no sheet to show it. A label that fits at
/// the default size and clips, wraps to a column of single letters or runs off
/// its row at twice that size is the commonest defect a resting-state sheet
/// hides, and the one a person who raised the system text size meets first.
///
/// So each card under `design/system/components/` has a catalog test, and each
/// catalog test carries a scene with `textScale: catalogTextScale`
/// (`CatalogScene.textScale`, in `catalog.dart`). A source scan, because the
/// catalog is skipped by the default gate and so cannot assert anything of its
/// own; read through `codeOf`, so a caption or a comment that names the
/// argument is not a use.
///
/// What the scene shows is the card's to decide, and what it finds is read off
/// the sheet (an overflow is also written beside it, as a finding). That a
/// scene exists is the one thing a test can hold.
void main() {
  const components = 'design/system/components';
  const catalogDir = 'test/design_catalog';

  /// Cards whose catalog test does not yet carry the scene. A card leaves this
  /// list the day it gains one, and the guard fails while it stays, so the list
  /// can only shrink.
  const pending = {'ContentCard', 'MediaPosterCard'};

  final cards = [
    for (final entry in Directory(components).listSync())
      if (entry is Directory) entry.uri.pathSegments.reversed.skip(1).first,
  ]..sort();

  test(
    'the scan has cards to read, and the scale it holds is twice the default',
    () {
      expect(cards.length, greaterThan(40));
      expect(
        catalogTextScale,
        2.0,
        reason:
            'The size every card is drawn at is part of the rule: lowering it '
            'would pass a card that breaks at the size people really set.',
      );
    },
  );

  test('every card has a catalog test that declares it', () {
    final missing = [
      for (final card in cards)
        if (!File(_testOf(catalogDir, card)).existsSync() ||
            !File(
              _testOf(catalogDir, card),
            ).readAsStringSync().contains("catalogCard(\n    '$card'"))
          card,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          'A card under $components needs ${_testOf(catalogDir, '<Card>')} '
          "declaring `catalogCard('<Card>', …)`: a widget with a card and no "
          'sheet is a promise nobody draws.',
    );
  });

  test('every catalog test belongs to a card', () {
    final orphans = [
      for (final file in Directory(catalogDir).listSync())
        if (file is File &&
            file.path.endsWith('_catalog_test.dart') &&
            !cards.any((card) => file.path == _testOf(catalogDir, card)))
          file.path,
    ];
    expect(
      orphans,
      isEmpty,
      reason: 'A catalog test whose card is gone is a sheet of nothing.',
    );
  });

  test('every card is drawn at 200% at least once', () {
    final without = [
      for (final card in cards)
        if (!pending.contains(card) &&
            !_hasTextScaleScene(
              File(_testOf(catalogDir, card)).readAsStringSync(),
            ))
          card,
    ];
    expect(
      without,
      isEmpty,
      reason:
          'Add a scene with `textScale: catalogTextScale` to each catalog '
          'test, drawing the states a person at twice the reading size meets '
          '(the label, the row, the longest sentence the card holds), and '
          'list it in the card README. Look at the sheet: an overflow lands '
          'in its findings file.',
    );
  });

  test('the pending list holds only cards that still lack the scene', () {
    final stale = [
      for (final card in pending)
        if (!cards.contains(card) ||
            _hasTextScaleScene(
              File(_testOf(catalogDir, card)).readAsStringSync(),
            ))
          card,
    ];
    expect(
      stale,
      isEmpty,
      reason:
          'These cards are drawn at 200% now (or are gone): take them off '
          '`pending`, which exists only to name what is still missing.',
    );
  });

  group('the matcher', () {
    test('counts a scene that sets the scale, and nothing else', () {
      const planted = '''
CatalogScene('a', (_) => w, textScale: catalogTextScale),
CatalogScene('b', (_) => w, textScale: 2),
// CatalogScene('c', (_) => w, textScale: catalogTextScale),
/// `textScale: catalogTextScale` in a doc comment.
CatalogScene('textScale: catalogTextScale', (_) => w),
CatalogScene('d', (_) => w, textScale: 1.5),
CatalogScene('e', (_) => w),
''';
      expect(_hasTextScaleScene(planted), isTrue);
      expect(
        _hasTextScaleScene(planted.split('\n').skip(2).join('\n')),
        isFalse,
      );
    });

    test('a card name becomes its test file', () {
      expect(
        _testOf('t', 'ServiceKpiPeek'),
        't/service_kpi_peek_catalog_test.dart',
      );
      expect(_testOf('t', 'AppCard'), 't/app_card_catalog_test.dart');
    });
  });
}

/// `ServiceKpiPeek` → `<dir>/service_kpi_peek_catalog_test.dart`.
String _testOf(String dir, String card) =>
    '$dir/${card.replaceAllMapped(RegExp(r'(?<!^)[A-Z]'), (m) => '_${m[0]}').toLowerCase()}_catalog_test.dart';

/// Whether [source] sets `textScale:` to the catalog's 200% (the constant, or
/// a literal 2), outside comments and string text.
bool _hasTextScaleScene(String source) => RegExp(
  r'\btextScale:\s*(catalogTextScale|2(\.0)?)\b(?!\.)',
).hasMatch(codeOf(source));
