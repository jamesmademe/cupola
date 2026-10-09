import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/discover/presentation/widgets/catalog_poster.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/home/presentation/widgets/home_header.dart';
import 'package:cupola/features/requests/presentation/requests_screen.dart';
import 'package:cupola/features/requests/presentation/widgets/requester_request_row.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The Home and the requester's page are one column: at a phone's width the
/// whole width, and wider than the reading well, the well, centred.
void main() {
  final now = DateTime(2026, 10, 9, 20, 30);

  Future<ProfileHarness> pump(
    WidgetTester tester,
    Widget child, {
    required ConfigProfile profile,
    required Size size,
  }) => pumpWithProfile(
    tester,
    profile,
    child: child,
    now: now,
    overrides: [calendarClockProvider.overrideWithValue(() => now)],
    surfaceSize: size,
  );

  test('the inset is nothing up to the well, then centres it', () {
    expect(AppBreakpoints.wellInset(390), 0);
    expect(AppBreakpoints.wellInset(AppBreakpoints.readingWell), 0);
    expect(
      AppBreakpoints.wellInset(1180),
      (1180 - AppBreakpoints.readingWell) / 2,
    );
  });

  for (final (name, width) in [('a phone', 390.0), ('a tablet', 1180.0)]) {
    testWidgets('the operator\'s Home on $name', (tester) async {
      final harness = await pump(
        tester,
        const HomeScreen(),
        profile: Profiles.p1,
        size: Size(width, 2400),
      );

      final header = tester.getRect(find.byType(HomeHeader));
      final well = width > AppBreakpoints.readingWell
          ? AppBreakpoints.readingWell
          : width;
      expect(header.width, well);
      expect(header.left, (width - well) / 2);

      await harness.unmount(tester);
    });
  }

  testWidgets('her page of requests in the well on a tablet', (tester) async {
    final harness = await pump(
      tester,
      const RequestsScreen(),
      profile: Profiles.p2,
      size: const Size(1180, 2400),
    );

    for (final row
        in tester
            .widgetList(find.byType(RequesterRequestRow))
            .map((row) => find.byWidget(row))) {
      final rect = tester.getRect(row);
      expect(rect.left, greaterThanOrEqualTo(AppBreakpoints.wellInset(1180)));
      expect(
        rect.right,
        lessThanOrEqualTo(1180 - AppBreakpoints.wellInset(1180)),
      );
    }
    expect(find.byType(RequesterRequestRow), findsWidgets);

    await harness.unmount(tester);
  });

  for (final (name, width) in [('a phone', 390.0), ('a tablet', 1180.0)]) {
    testWidgets('her shelves on $name run across the page, the first poster '
        'on the column\'s line', (tester) async {
      // Inside the well a shelf was cut at the well's edge, with the page
      // empty beside the cut.
      final harness = await pump(
        tester,
        const HomeScreen(),
        profile: Profiles.p2,
        size: Size(width, 3000),
      );

      final line = AppBreakpoints.wellInset(width) + AppSpacing.lg;
      final heading = find.text(HomeModule.trending.label);
      expect(heading, findsOneWidget);
      expect(tester.getTopLeft(heading).dx, line);
      final shelf = find.ancestor(
        of: find.byType(CatalogPoster).first,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.horizontal,
        ),
      );
      expect(tester.getRect(shelf).width, width);
      expect(tester.getTopLeft(find.byType(CatalogPoster).first).dx, line);

      await harness.unmount(tester);
    });
  }
}
