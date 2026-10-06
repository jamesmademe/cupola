import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/selection_pills.dart';

enum _Segment { history, blocklist }

Future<void> _pump(
  WidgetTester tester, {
  _Segment selected = _Segment.history,
  ValueChanged<_Segment>? onSelected,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Scaffold(
            body: SelectionPills<_Segment>(
              values: _Segment.values,
              selected: selected,
              labelBuilder: (value) => value.name,
              onSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SelectionPills', () {
    testWidgets('each pill is a button that announces its own selected state', (
      tester,
    ) async {
      // The control this replaces had no semantics node at all: no button role,
      // no accessible name and no selected state, so a screen-reader user could
      // neither tell it was tappable nor which segment was active.
      await _pump(tester);

      expect(
        find.semantics.byLabel('history'),
        containsSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      expect(
        find.semantics.byLabel('blocklist'),
        containsSemantics(
          isButton: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('tapping a pill reports that value', (tester) async {
      final tapped = <_Segment>[];
      await _pump(tester, onSelected: tapped.add);

      await tester.tap(find.text('blocklist'));
      await tester.pumpAndSettle();

      expect(tapped, [_Segment.blocklist]);
    });

    testWidgets('every pill clears the platform touch-target minimum', (
      tester,
    ) async {
      await _pump(tester);

      for (final label in _Segment.values.map((value) => value.name)) {
        expect(
          tester.getSize(find.text(label).hitTestable()).height,
          lessThanOrEqualTo(48.0),
          reason: '$label label should sit inside its pill',
        );
      }

      // 48dp is the stricter of the two platform minimums, and it is a floor on
      // the pill rather than a fixed height.
      for (final label in _Segment.values.map((value) => value.name)) {
        final pill = find.ancestor(
          of: find.text(label),
          matching: find.byType(Container),
        );
        expect(tester.getSize(pill.first).height, greaterThanOrEqualTo(48.0));
      }
    });

    testWidgets('does not overflow at an accessibility reading size', (
      tester,
    ) async {
      // The row scrolls horizontally and the pill has no fixed height, so a large
      // reading size must widen and heighten it rather than clip it. A
      // `RenderFlex` overflow would surface here as a pumped exception.
      await _pump(tester, textScaler: const TextScaler.linear(3.0));

      expect(tester.takeException(), isNull);
    });

    for (final brightness in Brightness.values) {
      testWidgets('the selected pill is the strong fill under the primary ink '
          '($brightness)', (tester) async {
        // The brand book: the nav pill, the same on every screen. It used to be a tint of
        // the page's service accent, whose label had to be walked because a
        // saturated accent over a 13% tint of itself measured under 2:1 on
        // paper; a monochrome pill has no hue to walk.
        final theme = brightness == Brightness.light
            ? AppTheme.lightTheme()
            : AppTheme.darkTheme();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SelectionPills<_Segment>(
                values: _Segment.values,
                selected: _Segment.history,
                labelBuilder: (value) => value.name,
                onSelected: (_) {},
              ),
            ),
          ),
        );

        final label = tester.widget<Text>(find.text('history'));
        expect(label.style?.color, theme.colorScheme.onSurface);
        final pill = tester.widget<Container>(
          find
              .ancestor(
                of: find.text('history'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(
          (pill.decoration! as BoxDecoration).color,
          CupolaRoom.forBrightness(brightness).fillStrong,
        );
      });
    }

    testWidgets('the row sits on the screen gutter, the wrap on its host\'s', (
      tester,
    ) async {
      // A scrolling row runs edge to edge and insets its first pill by the
      // screen gutter; a wrap is placed by a host already on the gutter, so it
      // adds no side inset of its own.
      Future<double> pillsLeft(Widget pills, Type layout) async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: pills)));
        return tester
            .getTopLeft(
              find
                  .descendant(
                    of: find.byType(SelectionPills<_Segment>),
                    matching: find.byType(layout),
                  )
                  .first,
            )
            .dx;
      }

      expect(
        await pillsLeft(
          SelectionPills<_Segment>(
            values: _Segment.values,
            selected: _Segment.history,
            labelBuilder: (value) => value.name,
            onSelected: (_) {},
          ),
          Row,
        ),
        16,
      );
      expect(
        await pillsLeft(
          SelectionPills<_Segment>.wrap(
            values: _Segment.values,
            selected: _Segment.history,
            labelBuilder: (value) => value.name,
            onSelected: (_) {},
          ),
          Wrap,
        ),
        0,
      );
    });
  });
}
