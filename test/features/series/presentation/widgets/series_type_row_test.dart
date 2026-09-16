import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/series/domain/sonarr_series_type.dart';
import 'package:cupola/features/series/presentation/widgets/series_type_row.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('SeriesTypeRow', () {
    testWidgets('announces itself as one node, not a loose value', (
      tester,
    ) async {
      // The row rule: a control says what it is. Before this the cell was a
      // bare `Text('Anime')` — a screen reader stopped on the word with nothing
      // saying what question it answered.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          SeriesTypeRow(
            rawValue: 'anime',
            accent: AppColors.sonarr,
            onChanged: (_) async {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(SeriesTypeRow)),
        matchesSemantics(
          label: 'Series type',
          value: 'Anime',
          hint: 'Changes how Sonarr numbers this series',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          // The load-bearing one. Merging the three children into a single
          // node also swallows the InkWell's tap action, which would leave a
          // node calling itself a button that a screen reader cannot activate.
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('writes the wire value, not the label it shows', (
      tester,
    ) async {
      SonarrSeriesType? written;
      await tester.pumpWidget(
        _host(
          SeriesTypeRow(
            rawValue: 'standard',
            accent: AppColors.sonarr,
            onChanged: (type) async => written = type,
          ),
        ),
      );

      await tester.tap(find.byType(SeriesTypeRow));
      await tester.pumpAndSettle();
      // By its description: the option's own label collides with the value the
      // row is already showing whenever the two happen to match.
      await tester.tap(find.text(SonarrSeriesType.anime.description));
      await tester.pumpAndSettle();

      expect(written, SonarrSeriesType.anime);
      // Sonarr answers 400 to the label; this is the whole reason the enum
      // carries a separate wire value.
      expect(written!.wireValue, 'anime');
    });

    testWidgets('choosing the value it already has writes nothing', (
      tester,
    ) async {
      // A no-op PUT against the series resource is not free: it is a
      // read-modify-write that can race a real one and costs a page reload.
      var calls = 0;
      await tester.pumpWidget(
        _host(
          SeriesTypeRow(
            rawValue: 'daily',
            accent: AppColors.sonarr,
            onChanged: (_) async => calls++,
          ),
        ),
      );

      await tester.tap(find.byType(SeriesTypeRow));
      await tester.pumpAndSettle();
      await tester.tap(find.text(SonarrSeriesType.daily.description));
      await tester.pumpAndSettle();

      expect(calls, 0);
    });

    testWidgets('a value Sonarr invented still prints', (tester) async {
      await tester.pumpWidget(
        _host(
          SeriesTypeRow(
            rawValue: 'sports',
            accent: AppColors.sonarr,
            onChanged: (_) async {},
          ),
        ),
      );

      // Not "Unknown", and not blank: the server is parsing releases with this
      // value, so hiding it hides the answer to "why is nothing importing".
      expect(find.text('Sports'), findsOneWidget);
    });

    testWidgets('a series the library does not hold stays a fact', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SeriesTypeRow(
            rawValue: 'standard',
            accent: AppColors.sonarr,
            onChanged: null,
          ),
        ),
      );

      expect(find.text('Standard'), findsOneWidget);
      // No chevron, because there is nothing to write to. A control that
      // cannot act is worse than a fact that never claimed to.
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();
      expect(
        find.text('How Sonarr reads episode numbers out of a release name'),
        findsNothing,
      );
    });

    testWidgets('a write in flight refuses a second tap', (tester) async {
      // Two overlapping read-modify-writes against one series resource lose
      // whichever landed first.
      var calls = 0;
      await tester.pumpWidget(
        _host(
          SeriesTypeRow(
            rawValue: 'standard',
            accent: AppColors.sonarr,
            isBusy: true,
            onChanged: (_) async => calls++,
          ),
        ),
      );

      await tester.tap(find.byType(SeriesTypeRow));
      await tester.pumpAndSettle();

      expect(calls, 0);
      // Still reachable and still readable — dimmed, never removed.
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    });
  });
}
