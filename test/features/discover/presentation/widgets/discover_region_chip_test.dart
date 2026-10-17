import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/features/discover/presentation/widgets/discover_region_chip.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// Records where the chip sent us, so the destination is asserted rather than
/// assumed.
String? lastLocation;

Future<void> _pumpChip(
  WidgetTester tester, {
  String region = 'IT',
  double textScale = 1.0,
}) async {
  lastLocation = null;

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: DiscoverRegionChip())),
      ),
      GoRoute(
        path: '/settings/region',
        builder: (context, state) {
          lastLocation = state.uri.toString();
          return const Scaffold(body: Text('Region settings'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [regionProvider.overrideWithValue(region)],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('DiscoverRegionChip', () {
    testWidgets('reads the region out of settings', (tester) async {
      await _pumpChip(tester, region: 'IT');

      expect(find.text('Region\u00A0· IT'), findsOneWidget);
    });

    testWidgets('follows the setting rather than holding a copy', (
      tester,
    ) async {
      await _pumpChip(tester, region: 'FR');

      expect(find.text('Region\u00A0· FR'), findsOneWidget);
      expect(find.text('Region\u00A0· IT'), findsNothing);
    });

    testWidgets('speaks the country, not the two-letter code', (tester) async {
      final handle = tester.ensureSemantics();

      await _pumpChip(tester, region: 'IT');

      // "IT" is read out as an initialism and is not a name.
      expect(
        tester.getSemantics(find.byType(DiscoverRegionChip)),
        containsSemantics(label: 'Region, Italy'),
      );

      handle.dispose();
    });

    testWidgets('a region with no name in the table still names itself', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await _pumpChip(tester, region: 'ZZ');

      expect(
        tester.getSemantics(find.byType(DiscoverRegionChip)),
        containsSemantics(label: 'Region, ZZ'),
      );

      handle.dispose();
    });

    testWidgets('is a door and not a filter', (tester) async {
      final handle = tester.ensureSemantics();

      await _pumpChip(tester);

      // Decision 32: a label with a destination. A selected or checked state
      // here would be the app claiming the chip narrows the rails, which region
      // is not a parameter on and cannot do.
      expect(
        tester.getSemantics(find.byType(DiscoverRegionChip)),
        containsSemantics(
          isButton: true,
          hasTapAction: true,
          isSelected: false,
          hasCheckedState: false,
          hasEnabledState: false,
        ),
      );
      expect(
        tester.getSemantics(find.byType(DiscoverRegionChip)).hint,
        contains('settings'),
      );

      handle.dispose();
    });

    testWidgets('lands on app Settings, Region', (tester) async {
      await _pumpChip(tester);

      await tester.tap(find.byType(DiscoverRegionChip));
      await tester.pumpAndSettle();

      expect(lastLocation, '/settings/region');
    });

    testWidgets('survives an accessibility reading size on a phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpChip(tester, textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(find.text('Region\u00A0· IT'), findsOneWidget);
    });

    testWidgets('keeps the row target even though the plate is smaller', (
      tester,
    ) async {
      await _pumpChip(tester);

      // The plate is ~30 tall; the target must not shrink to match it.
      expect(
        tester.getSize(find.byType(DiscoverRegionChip)).height,
        greaterThanOrEqualTo(48),
      );
    });
  });
}
