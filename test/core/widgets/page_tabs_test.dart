import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/page_tabs.dart';

enum _View {
  all('All'),
  downloads('Downloads'),
  requests('Requests'),
  history('History');

  const _View(this.label);
  final String label;
}

Future<void> _pump(
  WidgetTester tester, {
  List<_View> values = _View.values,
  _View selected = _View.all,
  ValueChanged<_View>? onSelected,
  double width = 390,
  double textScale = 1,
  String? semanticLabel,
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: PageTabs<_View>(
                values: values,
                selected: selected,
                labelBuilder: (view) => view.label,
                onSelected: onSelected ?? (_) {},
                semanticLabel: semanticLabel ?? 'Show',
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The top edge of each label's segment: segments in one row share it.
List<double> _rows(WidgetTester tester, Iterable<_View> views) => [
  for (final view in views) tester.getTopLeft(find.text(view.label)).dy,
];

void main() {
  group('PageTabs', () {
    testWidgets('each view is a button that announces whether it is the '
        'page', (tester) async {
      await _pump(tester, selected: _View.downloads);

      expect(
        find.semantics.byLabel('Downloads'),
        containsSemantics(isButton: true, isSelected: true),
      );
      for (final view in [_View.all, _View.requests, _View.history]) {
        expect(
          find.semantics.byLabel(view.label),
          containsSemantics(
            isButton: true,
            hasSelectedState: true,
            isSelected: false,
            hasTapAction: true,
          ),
          reason: view.label,
        );
      }
    });

    testWidgets('the group has a name, and one that the caller can set', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.bySemanticsLabel('Show'), findsOneWidget);

      await _pump(tester, semanticLabel: 'Activity views');
      expect(find.bySemanticsLabel('Activity views'), findsOneWidget);
    });

    testWidgets('a tap on another view reports it, a tap on the page does '
        'nothing', (tester) async {
      final tapped = <_View>[];
      await _pump(tester, selected: _View.requests, onSelected: tapped.add);

      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      expect(tapped, isEmpty);

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(tapped, [_View.history]);
    });

    testWidgets('every segment is a target of 44 at the default size', (
      tester,
    ) async {
      await _pump(tester);

      for (final view in _View.values) {
        final target = find.ancestor(
          of: find.text(view.label),
          matching: find.byType(InkWell),
        );
        expect(
          tester.getSize(target).height,
          greaterThanOrEqualTo(PageTabs.height - 2),
          reason: view.label,
        );
      }
    });

    testWidgets('the views share the track in one row while every label '
        'fits its share', (tester) async {
      // The test font is wider than the app's: a track wide enough for it.
      await _pump(tester, width: 800);

      expect(_rows(tester, _View.values).toSet(), hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 200% the track lays them two by two, and no word is '
        'cut', (tester) async {
      await _pump(tester, width: 800, textScale: 2);

      final tops = _rows(tester, _View.values);
      expect(tops.toSet(), hasLength(2));
      // All and Downloads above, Requests and History below.
      expect(tops[0], tops[1]);
      expect(tops[2], tops[3]);
      expect(tops[2], greaterThan(tops[0]));
      // The same share each: a short last row is as wide as the one above.
      final widths = {
        for (final view in _View.values)
          tester
              .getSize(
                find.ancestor(
                  of: find.text(view.label),
                  matching: find.byType(InkWell),
                ),
              )
              .width,
      };
      expect(widths, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short last row keeps its segment the width of the ones '
        'above', (tester) async {
      // Three views at 200% on a narrow track: two, then one.
      await _pump(
        tester,
        values: const [_View.all, _View.downloads, _View.requests],
        width: 280,
        textScale: 2,
      );

      final widths = [
        for (final view in [_View.all, _View.downloads, _View.requests])
          tester
              .getSize(
                find.ancestor(
                  of: find.text(view.label),
                  matching: find.byType(InkWell),
                ),
              )
              .width,
      ];
      expect(widths.toSet(), hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('two views are never laid two by two: there is no second '
        'row to a pair', (tester) async {
      await _pump(
        tester,
        values: const [_View.all, _View.downloads],
        width: 200,
        textScale: 2,
      );

      expect(_rows(tester, [_View.all, _View.downloads]).toSet(), hasLength(1));
    });

    testWidgets('draws in the light room too', (tester) async {
      await _pump(tester, theme: AppTheme.lightTheme());

      expect(find.text('All'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Reduce Motion: the thumb moves with no animation', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: PageTabs<_View>(
                values: _View.values,
                selected: _View.all,
                labelBuilder: (view) => view.label,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(AnimatedContainer), findsNWidgets(4));
      for (final box in tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      )) {
        expect(box.duration, Duration.zero);
      }
    });
  });
}
