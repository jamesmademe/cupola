import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/arr_tab_screen.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_history_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_library_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_providers_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_wanted_screen.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

/// What the router hands every hosted tab screen as `topPadding`: the service
/// band plus the tab bar, **without** the phone's top inset. Mirrored here
/// because the router's own constant is private.
const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

/// An iPhone 17 Pro in portrait, the surface the defect was seen on.
const Size _phone = Size(402, 874);
const double _statusBar = 62;

/// The tabs of a service room on a notched phone: the band, the tab bar under
/// it, and the tab's own screen under both.
///
/// **The bar is placed an inset below `kToolbarHeight`**, because the band
/// consumes the inset (see `ServiceHomeScreen.bandHeightOf`). A hosted screen
/// is handed the bare chrome height, so it is the screen's job to add the
/// inset, through a `SafeArea` or through `MediaQuery`. A test surface with no
/// inset cannot tell a screen that does from one that does not, which is how a
/// tab's first row sat under the bar until someone looked at a real iPhone.
void main() {
  /// The phone, with its notch. Set on the view rather than wrapped around the
  /// app, so the `MediaQuery` every widget reads is the one a device builds.
  void usePhone(WidgetTester tester) {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = _phone
      ..padding = const FakeViewPadding(top: _statusBar)
      ..viewPadding = const FakeViewPadding(top: _statusBar);
    addTearDown(tester.view.reset);
  }

  Future<void> pumpHosted(
    WidgetTester tester, {
    required ServiceKey service,
    required ServiceTab tab,
    required Widget child,
    List<Override> overrides = const [],
  }) async {
    usePhone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(configured: [service]),
          ...overrides,
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: ServiceHomeScreen(
              service: service,
              child: ServiceTabScaffold(
                service: service,
                tab: tab,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Where the tab bar ends: the line no hosted content may start above.
  double barBottom(WidgetTester tester) => tester
      .getRect(
        find.ancestor(
          of: find.byType(ServiceTabBar),
          matching: find.byType(GlassSurface),
        ),
      )
      .bottom;

  void expectClearsTheBar(WidgetTester tester, Finder content) {
    expect(content, findsWidgets);
    expect(
      tester.getTopLeft(content.first).dy,
      greaterThanOrEqualTo(barBottom(tester)),
      reason: 'the first content starts under the tab bar',
    );
  }

  group('the phone the cases run on', () {
    testWidgets('has a status bar, and the bar sits an inset below the band', (
      tester,
    ) async {
      // The fixture itself, asserted: if the inset ever stopped reaching the
      // tree, every case below would pass for the wrong reason.
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.queue,
        child: const SizedBox.expand(),
      );

      expect(
        MediaQuery.paddingOf(tester.element(find.byType(ServiceTabBar))).top,
        _statusBar,
      );
      expect(
        barBottom(tester),
        _statusBar + kToolbarHeight + ServiceTabBar.height,
      );
      expect(barBottom(tester), _statusBar + _hostedTopPadding);
    });
  });

  group('ArrTabScreen clears the glass bars', () {
    final overrides = <Override>[
      radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
    ];

    testWidgets('an empty queue starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.queue,
        overrides: overrides,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.queue,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.text('Queue is empty'), findsOneWidget);
      expectClearsTheBar(tester, find.byType(AppEmptyState));
      // The picture the user reported: the icon, not just the well around it.
      expectClearsTheBar(tester, find.byIcon(Icons.download_done_rounded));
    });

    testWidgets('an empty history starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.history,
        overrides: overrides,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.history,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.text('No history yet'), findsOneWidget);
      expectClearsTheBar(tester, find.byType(AppEmptyState));
    });

    testWidgets('Wanted draws its pills below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.wanted,
        overrides: overrides,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.wanted,
          topPadding: _hostedTopPadding,
        ),
      );

      // The pills are Wanted's first row: missing against cutoff unmet.
      expectClearsTheBar(tester, find.text('Missing'));
    });

    testWidgets('a queue still loading starts below the tab bar', (
      tester,
    ) async {
      // Not the empty state: the skeleton is the first thing every tab shows,
      // and it rides the same padding.
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.queue,
        overrides: [
          radarrServiceProvider.overrideWith((ref) => _NeverAnswers()),
        ],
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.queue,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.byType(AppEmptyState), findsNothing);
      expectClearsTheBar(tester, find.byType(ShimmerList));
    });
  });

  group('Bazarr tabs clear the glass bars', () {
    List<Override> over(FakeBazarrService service) => [
      bazarrServiceProvider.overrideWith((ref) => service),
    ];

    testWidgets('Wanted draws its Episodes and Movies bar below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.wanted,
        overrides: over(FakeBazarrService()),
        child: const BazarrWantedScreen(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(TabBar));
    });

    testWidgets('the Series library starts below the tab bar', (tester) async {
      final service = FakeBazarrService()
        ..seriesResult = const BazarrPagedResult(
          data: [
            BazarrSeries(
              sonarrSeriesId: 1,
              title: 'Foundation',
              year: 2021,
              monitored: true,
            ),
          ],
          total: 1,
        );
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.series,
        overrides: over(service),
        child: const BazarrLibraryScreen.series(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.text('Foundation'), findsOneWidget);
      expectClearsTheBar(tester, find.text('Foundation'));
    });

    testWidgets('the Movies library starts below the tab bar', (tester) async {
      final service = FakeBazarrService()
        ..moviesResult = const BazarrPagedResult(
          data: [
            BazarrMovie(
              radarrId: 1,
              title: 'Arrival',
              year: 2016,
              monitored: true,
            ),
          ],
          total: 1,
        );
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.movies,
        overrides: over(service),
        child: const BazarrLibraryScreen.movies(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.textContaining('Arrival'), findsOneWidget);
      expectClearsTheBar(tester, find.textContaining('Arrival'));
    });

    testWidgets('a library still loading starts below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.series,
        overrides: over(_BazarrNeverAnswers()),
        child: const BazarrLibraryScreen.series(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(ShimmerPlaceholder));
    });

    testWidgets('History draws its filter pills below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.history,
        overrides: over(FakeBazarrService()),
        child: const BazarrHistoryScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, _selectionPills);
    });

    testWidgets('Providers starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.bazarr,
        tab: ServiceTab.providers,
        overrides: over(FakeBazarrService()),
        child: const BazarrProvidersScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(SectionHeader));
    });
  });
}

/// A Radarr that never answers its queue, so the screen stays on its skeleton.
class _NeverAnswers extends FakeRadarrService {
  @override
  Future<List<dynamic>> getQueue({Map<String, dynamic>? queryParameters}) =>
      Completer<List<dynamic>>().future;
}

/// A Bazarr that never answers a library page, so the list stays on its shimmer.
class _BazarrNeverAnswers extends FakeBazarrService {
  @override
  Future<BazarrPagedResult<BazarrSeries>> getSeries({
    int start = 0,
    int length = 50,
  }) => Completer<BazarrPagedResult<BazarrSeries>>().future;
}

/// The filter pills a screen leads with. `SelectionPills` is generic over a
/// screen's private enum, so it can only be found by its name.
final _selectionPills = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString().startsWith('SelectionPills'),
  description: 'SelectionPills',
);
