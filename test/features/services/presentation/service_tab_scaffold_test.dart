import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/services/presentation/service_tab_placeholder.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

void main() {
  group('serviceTabOf / isServiceTabRoot', () {
    test('reads the tab off the path', () {
      expect(
        serviceTabOf(ServiceKey.radarr, '/dashboard/radarr/library'),
        ServiceTab.library,
      );
      expect(
        serviceTabOf(ServiceKey.radarr, '/dashboard/radarr/library/movie/42'),
        ServiceTab.library,
      );
    });

    test('a tab another service owns is not this service\'s', () {
      // `rss` is a qBittorrent view. A link naming it under Radarr is not a
      // place on Radarr, and answering with the tab would light a bar entry
      // that does not exist.
      expect(serviceTabOf(ServiceKey.radarr, '/dashboard/radarr/rss'), isNull);
      expect(
        serviceTabOf(ServiceKey.qbittorrent, '/dashboard/qbittorrent/rss'),
        ServiceTab.rss,
      );
    });

    test('another service\'s path is not read as this one\'s', () {
      expect(
        serviceTabOf(ServiceKey.radarr, '/dashboard/sonarr/library'),
        isNull,
      );
      expect(serviceTabOf(ServiceKey.radarr, '/dashboard/radarr'), isNull);
      expect(serviceTabOf(ServiceKey.radarr, '/dashboard'), isNull);
    });

    test('a tab root is three segments; a pushed page is more', () {
      // The band the shell draws asks exactly this question, because it cannot
      // be covered by the page that wants it gone.
      expect(
        isServiceTabRoot(ServiceKey.radarr, '/dashboard/radarr/library'),
        isTrue,
      );
      expect(
        isServiceTabRoot(
          ServiceKey.radarr,
          '/dashboard/radarr/library/movie/42',
        ),
        isFalse,
      );
    });

    test('TrueNAS has no tabs, so nothing is one of its roots', () {
      expect(
        serviceTabOf(ServiceKey.truenas, '/dashboard/truenas/storage'),
        isNull,
      );
      expect(
        isServiceTabRoot(ServiceKey.truenas, '/dashboard/truenas/storage'),
        isFalse,
      );
    });
  });

  group('ServiceTabScaffold', () {
    // The inset a notched iPhone or a cutout Android hands the app. Zero on
    // the default test surface, which is the whole reason the bar could sit an
    // inset too high for as long as it did.
    const topInset = 47.0;

    Future<void> pump(
      WidgetTester tester,
      ServiceKey service, {
      double inset = 0,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: EdgeInsets.only(top: inset)),
            child: Scaffold(
              body: ServiceTabScaffold(
                service: service,
                tab: ServiceTab.overview,
                child: const Text('tab content'),
              ),
            ),
          ),
        ),
      ),
    );

    /// The whole chrome as the shell draws it: the band over the bar over the
    /// tab's own page, which is the only arrangement that can be asked whether
    /// the two bands overlap.
    Future<void> pumpUnderTheBand(
      WidgetTester tester, {
      required double inset,
    }) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: EdgeInsets.only(top: inset)),
              child: Scaffold(
                body: ServiceHomeScreen(
                  service: ServiceKey.radarr,
                  child: const ServiceTabScaffold(
                    service: ServiceKey.radarr,
                    tab: ServiceTab.overview,
                    child: Text('tab content'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Rect bandRect(WidgetTester tester) => tester.getRect(
      find.ancestor(
        of: find.byKey(const ValueKey('service-home-title-radarr')),
        matching: find.byType(GlassSurface),
      ),
    );

    Rect barRect(WidgetTester tester) => tester.getRect(
      find.ancestor(
        of: find.byType(ServiceTabBar),
        matching: find.byType(GlassSurface),
      ),
    );

    testWidgets('draws the bar over the tab\'s content', (tester) async {
      await pump(tester, ServiceKey.radarr);

      expect(find.text('tab content'), findsOneWidget);
      expect(find.byType(ServiceTabBar), findsOneWidget);
    });

    testWidgets('the bar sits under the shell\'s band, not over it', (
      tester,
    ) async {
      // The service app bar is drawn by the shell above every branch; this one
      // is drawn by the branch. They stack, they do not overlap.
      await pump(tester, ServiceKey.radarr);

      expect(tester.getTopLeft(find.byType(ServiceTabBar)).dy, kToolbarHeight);
    });

    testWidgets('the top inset pushes the bar down with the band', (
      tester,
    ) async {
      // The band consumes the inset, so it is drawn an inset lower than
      // `kToolbarHeight` alone would say. A bar pinned to the bare constant
      // ends up underneath it by exactly the inset — on every notched iPhone
      // and every cutout Android, invisibly, because a test surface with no
      // inset cannot tell the two numbers apart.
      await pump(tester, ServiceKey.radarr, inset: topInset);

      expect(
        tester.getTopLeft(find.byType(ServiceTabBar)).dy,
        topInset + kToolbarHeight,
      );
    });

    testWidgets('the band and the bar meet, on a surface with an inset', (
      tester,
    ) async {
      await pumpUnderTheBand(tester, inset: topInset);

      final band = bandRect(tester);
      final bar = barRect(tester);

      // Flush: the bar starts exactly where the band ends. Not less — that is
      // the overlap — and not more, which would be a strip of unclaimed
      // gradient between two bands that read as one surface.
      expect(band.bottom, topInset + kToolbarHeight);
      expect(bar.top, band.bottom);
      expect(bar.overlaps(band), isFalse);

      // And the pair ends where every hosted screen reserves room to: its own
      // inset (from a `SafeArea` or from `MediaQuery`) plus the chrome height
      // the router hands it as `topPadding`.
      expect(bar.bottom, topInset + kToolbarHeight + ServiceTabBar.height);
    });

    testWidgets('with no inset the two still meet', (tester) async {
      // The regression this replaces: the pair was only ever flush here.
      await pumpUnderTheBand(tester, inset: 0);

      expect(barRect(tester).top, bandRect(tester).bottom);
      expect(bandRect(tester).bottom, kToolbarHeight);
    });

    testWidgets('TrueNAS draws its content and no bar', (tester) async {
      await pump(tester, ServiceKey.truenas);

      expect(find.text('tab content'), findsOneWidget);
      expect(find.byType(ServiceTabBar), findsNothing);
    });
  });

  group('ServiceTabPlaceholder', () {
    Future<void> pump(WidgetTester tester, {required bool configured}) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentSettingsProvider.overrideWith(
                (ref) => configured
                    ? const SettingsModel(
                        instances: [
                          ServiceInstance(
                            id: 'radarr',
                            service: ServiceKey.radarr,
                            url: 'http://radarr.lan',
                            credential: 'k',
                          ),
                        ],
                      )
                    : const SettingsModel(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme(),
              home: Scaffold(
                body: ServiceTabPlaceholder(
                  service: ServiceKey.radarr,
                  tab: ServiceTab.calendar,
                ),
              ),
            ),
          ),
        );

    testWidgets('a service that is not set up says so first', (tester) async {
      // "The Calendar is empty" would be a claim about a server this app has
      // never spoken to. The emptiness of a thing you cannot see is not a fact.
      await pump(tester, configured: false);

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      // And specifically NOT the empty-tab copy: the two share a well, so the
      // type alone would not tell them apart.
      expect(find.textContaining('is not here yet'), findsNothing);
    });

    testWidgets('a configured service gets the empty well, not an error', (
      tester,
    ) async {
      // Nothing failed, so nothing wears alarm chrome — the same well the
      // queue shows when the queue is genuinely empty.
      await pump(tester, configured: true);

      expect(find.byType(NotConfiguredPlaceholder), findsNothing);
      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text('Calendar is not here yet'), findsOneWidget);
    });

    testWidgets('the well can scroll, so its copy is not clipped', (
      tester,
    ) async {
      // A leaf that cannot scroll clips its own second line at an
      // accessibility reading size, and this copy is two lines at every size.
      await pump(tester, configured: true);

      expect(find.byType(AppEmptyStatePage), findsOneWidget);
    });
  });
}
