/// The Home and the Stack, module by module.
///
/// Every test here guards a **rule**, not a rendering: the order of the modules
/// on each page, what leads Needs you, the cap per size class, that a probe
/// still out is not a fault, that a figure nobody could take reads `—` and not
/// `0`, and that a control whose target is not configured is dimmed but still
/// reachable. Nothing asserts a hex or a pixel: those are the design system's
/// to change and this file's to survive.
///
/// The page that was the Dashboard is two now. The Home keeps Needs you, what
/// is in progress, what is coming up, what arrived, what is moving and what
/// waits for an answer, in the order the person keeps them; the Stack keeps the
/// headline, the band and the matrix of services. The empty state is on both, so its test runs on both. The band is
/// the Stack's: on the Home a service that did not answer leads Needs you, in
/// the same words.
///
/// The fold tests that used to fill most of this file are gone, and the two that
/// replace them are the reason they are gone rather than deleted: the stack now
/// has **one density**, so a card carries its figures on arrival and there is no
/// persisted preference, no demo and no per-domain toggle to restore.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/core/widgets/setup_doors.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/home/presentation/widgets/requests_module.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/home/presentation/widgets/home_header.dart';
import 'package:cupola/features/home/presentation/widgets/needs_you_banner.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/service_signal.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/service_matrix.dart';
import 'package:cupola/features/services/presentation/services_alert_band.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/decision_rows.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets("the Home's modules are in the settled order", (tester) async {
    await _pumpPage(
      tester,
      _Page.home,
      decisions: [_stall('Furiosa', at: DateTime.utc(2024))],
    );

    // Read off the list rather than off the screen: the modules below the fold
    // are built lazily, so a y-coordinate comparison would be testing the
    // viewport height. The day and, under it, the line a cold start's last
    // drawing says itself in, then what needs me, what is featured, what is
    // in progress, what is coming up, what arrived, what is moving, what waits
    // for an answer and who is watching, and the Home's own two rows at its
    // foot: Set up next and the way to Edit Home. Featured, Now playing and
    // Continue watching hold their place with nothing to show: they step aside
    // by drawing nothing, not by leaving the list.
    expect(_regionsOnPage(tester), [
      'HomeHeader',
      'HomeAsOfLine',
      'NeedsYouBanner',
      'HomeFeaturedModule',
      'HomeContinueWatchingModule',
      'HomeComingUpModule',
      'HomeArrivedModule',
      'HomeDownloadsModule',
      'HomeRequestsModule',
      'HomeNowPlayingModule',
      'SetUpNextModule',
      'EditHomeRow',
      'SizedBox',
    ]);
  });

  testWidgets('what leads Needs you stands above the day\'s modules', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _Page.home,
      instanceSummary: (key) => _summary(key.service, online: true),
      summary: (service) => _summary(service, online: true),
      decisions: [_stall('Furiosa', at: DateTime.utc(2024))],
      arrivals: [_imported('Poor Things', ago: const Duration(hours: 2))],
    );

    // The lead is the first thing under the day, and Arrived is under it.
    expect(
      _yOf(tester, find.byType(HomeHeader)),
      lessThan(_yOf(tester, find.text('Furiosa is stuck'))),
    );
    expect(
      _yOf(tester, find.text('Furiosa is stuck')),
      lessThan(_yOf(tester, find.text('Arrived'))),
    );
  });

  testWidgets("the Stack's regions are in the settled order", (tester) async {
    await _pumpPage(tester, _Page.stack);

    // The headline says whether everything is all right, the band names what is
    // not, and the matrix, the launcher, comes last: the fleet is all this page
    // holds.
    expect(_regionsOnPage(tester), [
      '_StackHeadline',
      'ServicesAlertBand',
      'ServiceMatrix',
    ]);
  });

  testWidgets('a card whose figures failed reads an em dash, not a shimmer', (
    tester,
  ) async {
    // The Dockge bug: the probe answered, the figures read failed, and the
    // card shimmered for good because failure and "still coming" were both
    // null.
    await _pumpPage(
      tester,
      _Page.stack,
      signalPairFuture: (service) => service == ServiceKey.sonarr
          ? Future.error(Exception('Sonarr did not answer'))
          : Future.value(null),
    );
    await tester.pump();

    final sonarr = find.byKey(const ValueKey('service-matrix-cell-sonarr'));
    await tester.scrollUntilVisible(sonarr, 200);
    expect(
      find.descendant(of: sonarr, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sonarr, matching: find.byType(ShimmerPlaceholder)),
      findsNothing,
    );
    // And the band's line does not count it clean.
    expect(find.textContaining('Sonarr figures unavailable'), findsOneWidget);
  });

  for (final page in _Page.values) {
    group('with nothing set up, the ${page.name}', () {
      // The front door until something answers, on the first tab and on the
      // Stack alike: the same door the Welcome has, in the same words. It
      // opens Connect directly, since the claim was made on the way in and
      // this page is already past it. Its headline used to use the word for a
      // service that stayed silent, and its door borrowed the old pick step's
      // title while opening Connections.
      testWidgets('says nothing is set up and opens Connect', (tester) async {
        String? opened;
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (context, state) => _screen(page)),
            GoRoute(
              path: ServiceRoutes.welcomeConnect,
              builder: (context, state) {
                opened = state.uri.path;
                return const SizedBox.shrink();
              },
            ),
          ],
        );
        addTearDown(router.dispose);

        await _pumpPage(
          tester,
          page,
          router: router,
          settings: const SettingsModel(),
        );

        expect(find.text('Nothing is set up yet.'), findsOneWidget);
        expect(find.text('Nothing answers yet.'), findsNothing);
        expect(find.text('Pick your services'), findsNothing);
        // One door, with what it leads with said under it, and no count of
        // services "waiting" for an address.
        expect(find.text('Set up a service'), findsOneWidget);
        expect(find.text(SetupDoors.setUpHint), findsOneWidget);
        expect(find.textContaining('waiting for an address'), findsNothing);
        expect(find.byType(FilledButton), findsOneWidget);

        await tester.tap(find.text('Set up a service'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(opened, ServiceRoutes.welcomeConnect);
      });

      testWidgets('offers copying from another device between the other '
          'two doors, and opens the screen that copies', (tester) async {
        String? opened;
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (context, state) => _screen(page)),
            GoRoute(
              path: ServiceRoutes.welcomePair,
              builder: (context, state) {
                opened = state.uri.path;
                return const SizedBox.shrink();
              },
            ),
          ],
        );
        addTearDown(router.dispose);

        await _pumpPage(
          tester,
          page,
          router: router,
          settings: const SettingsModel(),
        );

        expect(find.text('Copy from another device'), findsOneWidget);
        expect(find.text(SetupDoors.copyHint), findsOneWidget);
        expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);
        // A text door, not a second fill.
        expect(find.byType(FilledButton), findsOneWidget);
        final doors = [
          for (final label in [
            'Set up a service',
            'Copy from another device',
            'I have a Seerr account',
          ])
            tester.getTopLeft(find.text(label)).dy,
        ];
        expect(doors, [...doors]..sort());

        await tester.tap(find.text('Copy from another device'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(opened, ServiceRoutes.welcomePair);
      });

      testWidgets('keeps the ring still: nothing is set up, nothing moves', (
        tester,
      ) async {
        await _pumpPage(tester, page, settings: const SettingsModel());

        // Settled: a ring that spun would keep scheduling frames for ever.
        await tester.pumpAndSettle();
        expect(find.byType(ServiceRing), findsOneWidget);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      // The date is the Home's, whatever is set up; the Stack never had one.
      testWidgets(
        page == _Page.home
            ? 'keeps the Home\'s date above the ring'
            : 'has no date above the ring',
        (tester) async {
          await _pumpPage(tester, page, settings: const SettingsModel());

          expect(
            find.byType(HomeHeader),
            page == _Page.home ? findsOneWidget : findsNothing,
          );
        },
      );
    });
  }

  group('the header', () {
    testWidgets('counts connections folded per service, and says degraded', (
      tester,
    ) async {
      // Two Radarr, one of them dark: the service still answers, so it is not
      // unreachable: it is degraded, and the sum still closes over the
      // configured services.
      await _pumpPage(
        tester,
        _Page.stack,
        settings: _twoRadarrSettings,
        instanceSummary: (key) =>
            _summary(key.service, online: key.instanceId != 'radarr-hd'),
      );

      expect(
        find.textContaining('1 of 1 answering · 1 degraded'),
        findsOneWidget,
      );
    });

    testWidgets('a probe still out reads as checking, and is not a fault', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.stack,
        // Never completes: the header has to be honest about a reading in
        // progress rather than reporting the absence of an answer as a failure.
        instanceSummaryFuture: (_) => Completer<ServiceSummary>().future,
        summaryFuture: (_) => Completer<ServiceSummary>().future,
      );

      final line = _textContaining(tester, 'answering');
      expect(line, contains('checking'));
      // Nothing has failed; we simply do not know yet.
      expect(line, isNot(contains('unreachable')));
    });

    testWidgets('the age is bucketed, never in seconds', (tester) async {
      await _pumpPage(tester, _Page.stack);
      final line = _textContaining(tester, 'answering');
      expect(line, contains('refreshed just now'));
      expect(line, isNot(contains('second')));
    });
  });

  // The band is the Stack's: what stopped answering is the first thing it says.
  group('the alert band, the stack', () {
    const page = _Page.stack;

    testWidgets('names the offenders in the settled words', (tester) async {
      await _pumpPage(tester, page);

      // Lidarr is the configured service that does not answer in the fixture.
      // Scoped to the band: the same sentence is what a module whose sources are
      // dark prints in place of its empty copy, and the two sharing one string
      // is the point.
      // 800pt wide in a widget test, so the band carries its second sentence:
      // the consequence is what a wide surface has room for.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('services-alert-band')),
          matching: find.textContaining('Lidarr did not answer.'),
        ),
        findsOneWidget,
      );
      // One offender, so the bare verb: `Retry both` is for exactly two.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('services-alert-band')),
          matching: find.text('Retry'),
        ),
        findsOneWidget,
      );
      // The action is the fix: the second control leads where the address is.
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('retry stays brand indigo, never the error tone', (
      tester,
    ) async {
      await _pumpPage(tester, page);

      final context = tester.element(find.byType(ServicesAlertBand));
      final scheme = Theme.of(context).colorScheme;
      final retry = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const ValueKey('services-alert-band')),
              matching: find.text('Retry'),
            )
            .first,
      );
      expect(retry.style?.color, scheme.primary);
      expect(retry.style?.color, isNot(scheme.error));
    });

    testWidgets('the phone prints the first sentence only', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await _pumpPage(tester, page);

      // One line of room, and the name of the service is the half that cannot
      // be dropped.
      expect(find.text('Lidarr did not answer.'), findsWidgets);
      expect(find.textContaining('missing from this page'), findsNothing);
    });

    testWidgets('stays silent for a degraded service the header names', (
      tester,
    ) async {
      // Two Radarr, the dark one being the lens. The band used to read the
      // lensed summary, so it printed "Radarr did not answer." directly under a
      // header that had just called Radarr answering. One fold now: the header
      // counts it degraded, the band names nobody.
      await _pumpPage(
        tester,
        page,
        settings: _twoRadarrSettings,
        instanceSummary: (key) =>
            _summary(key.service, online: key.instanceId != 'radarr-hd'),
        summary: (service) => _summary(service, online: false),
      );

      expect(find.textContaining('1 degraded'), findsOneWidget);
      expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);
    });

    testWidgets('is absent entirely when the whole stack answers', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        page,
        instanceSummary: (key) => _summary(key.service, online: true),
        summary: (service) => _summary(service, online: true),
      );

      expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);
    });
  });

  // On the Home the band is gone: a service that did not answer leads Needs
  // you, in the band's own words, and its line is its Retry.
  group('Needs you, the home, for a service that did not answer', () {
    const page = _Page.home;

    Finder inNeedsYou(Finder matching) =>
        find.descendant(of: find.byType(NeedsYouLine), matching: matching);

    testWidgets('names the offenders in the settled words', (tester) async {
      await _pumpPage(tester, page);

      // Lidarr is the configured service that does not answer in the fixture.
      // The band's sentence as a clause, and the time the probe found it
      // silent; the Home has no band, and no Stack-only `Settings` control.
      expect(
        inNeedsYou(
          find.textContaining(
            RegExp(r'^Lidarr did not answer at \d{2}:\d{2}$'),
          ),
        ),
        findsOneWidget,
      );
      // One offender, so the bare verb: `Retry both` is for exactly two.
      expect(inNeedsYou(find.text('Retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);
    });

    testWidgets('retry stays in the ink, never the error tone', (tester) async {
      await _pumpPage(tester, page);

      final context = tester.element(find.byType(NeedsYouLine));
      final scheme = Theme.of(context).colorScheme;
      final retry = tester.widget<Text>(inNeedsYou(find.text('Retry')));
      expect(retry.style?.color, CupolaRoom.of(context).ink);
      expect(retry.style?.color, isNot(scheme.error));
    });

    testWidgets('the phone prints one sentence, and no second', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await _pumpPage(tester, page);

      // One line of room, and the name of the service is the half that cannot
      // be dropped.
      expect(
        find.textContaining(RegExp(r'^Lidarr did not answer at ')),
        findsOneWidget,
      );
      expect(find.textContaining('missing from this page'), findsNothing);
    });

    testWidgets('stays silent for a degraded service the header names', (
      tester,
    ) async {
      // Two Radarr, the dark one being the lens: the service answers, so Needs
      // you names nobody.
      await _pumpPage(
        tester,
        page,
        settings: _twoRadarrSettings,
        instanceSummary: (key) =>
            _summary(key.service, online: key.instanceId != 'radarr-hd'),
        summary: (service) => _summary(service, online: false),
      );

      expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);
      expect(find.textContaining('did not answer'), findsNothing);
      expect(find.byType(NeedsYouLine), findsNothing);
    });

    testWidgets('is absent entirely when the whole stack answers', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        page,
        instanceSummary: (key) => _summary(key.service, online: true),
        summary: (service) => _summary(service, online: true),
      );

      expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);
      expect(find.byType(NeedsYouLine), findsNothing);
    });
  });

  group('Needs you', () {
    Finder inNeedsYou(Finder matching) =>
        find.descendant(of: find.byType(NeedsYouLine), matching: matching);

    testWidgets('the oldest of equal faults leads, and backlog is no fault', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        instanceSummary: (key) => _summary(key.service, online: true),
        summary: (service) => _summary(service, online: true),
        decisions: [
          _request('Severance', at: DateTime.utc(2024, 1, 1)),
          _stall('The Zone of Interest', at: DateTime.utc(2024, 5, 2)),
          _stall('Fantasia', at: DateTime.utc(2024, 5, 1)),
        ],
      );

      // Two stalls of one size: the oldest leads, as the ranking has it. The
      // request is the oldest item by four months and is no part of the line
      // or of its count: it is backlog, and waits in Requests.
      expect(inNeedsYou(find.text('Fantasia is stuck')), findsOneWidget);
      expect(inNeedsYou(find.text('+1')), findsOneWidget);
      expect(find.text('The Zone of Interest'), findsNothing);
      expect(inNeedsYou(find.text('Severance')), findsNothing);
      expect(
        _yOf(tester, find.text('Fantasia is stuck')),
        lessThan(_yOf(tester, find.text('Severance'))),
      );
    });

    testWidgets('one line, and the faults beyond its lead are counted', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        instanceSummary: (key) => _summary(key.service, online: true),
        summary: (service) => _summary(service, online: true),
        decisions: [
          for (var i = 0; i < 5; i++)
            _stall('Stalled $i', at: DateTime.utc(2024, 1, i + 1)),
        ],
      );

      // The cap hides rows, and Needs you has none: one line, and the count of
      // what it leaves out.
      expect(inNeedsYou(find.text('Stalled 0 is stuck')), findsOneWidget);
      expect(inNeedsYou(find.text('+4')), findsOneWidget);
      expect(find.text('Stalled 1'), findsNothing);
      expect(find.text('Review'), findsOneWidget);
    });

    testWidgets('a group of equal faults is one line that says how many', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        instanceSummary: (key) => _summary(key.service, online: true),
        summary: (service) => _summary(service, online: true),
        decisions: groupDecisions([
          for (var i = 0; i < 18; i++)
            _blocked('Episode $i', at: DateTime.utc(2024, 1, i + 1)),
        ]),
      );

      // APP-04: a blocked import was filed as a stall, and eighteen of them
      // were eighteen rows. One line, and its figure is what they stand for.
      expect(
        inNeedsYou(find.text('18 downloads need a manual import')),
        findsOneWidget,
      );
      expect(inNeedsYou(find.textContaining('stuck')), findsNothing);
      expect(inNeedsYou(find.textContaining(RegExp(r'^\+\d'))), findsNothing);
    });

    testWidgets('is absent, and Requests with it, when nothing is waiting', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        instanceSummary: (key) => _summary(key.service, online: true),
        summary: (service) => _summary(service, online: true),
        decisions: const [],
      );

      expect(find.byType(NeedsYouLine), findsNothing);
      expect(find.text('Needs you'), findsNothing);
      expect(find.text('Requests'), findsNothing);
    });
  });

  group('Requests', () {
    testWidgets('the phone shows three, and says how many wait', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        decisions: [
          for (var i = 0; i < 5; i++)
            _request('Requested $i', at: DateTime.utc(2024, 1, i + 1)),
        ],
      );

      // Three rows, and the two the cap dropped are simply not built.
      expect(find.text('Requested 0'), findsOneWidget);
      expect(find.text('Requested 2'), findsOneWidget);
      expect(find.text('Requested 3'), findsNothing);
      // The cap hides rows; the heading must not hide the count.
      expect(find.text('5 wait for you'), findsOneWidget);
    });

    testWidgets('a pending request keeps both of its decisions', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        decisions: [_request('A Quiet Place', at: DateTime.utc(2024, 1, 1))],
      );

      expect(
        find.descendant(
          of: find.byType(HomeRequestsModule),
          matching: find.byTooltip('Approve A Quiet Place'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(HomeRequestsModule),
          matching: find.byTooltip('Decline A Quiet Place'),
        ),
        findsOneWidget,
      );
    });
  });

  // The Home leads with one line and no longer lists the decisions, so the
  // row, which still carries each kind's control, is mounted on its own, with
  // the decisions the app's own provider builds.
  group('a decision row', () {
    testWidgets(
      'a control whose target is not configured is dimmed but reachable',
      (tester) async {
        await _pumpPage(
          tester,
          _Page.home,
          screen: const Scaffold(body: ProvidedDecisionRows()),
          decisions: [
            _stall(
              'Furiosa',
              at: DateTime.utc(2024, 1, 1),
              // qBittorrent is not in the fixture's settings.
              requires: ServiceKey.qbittorrent,
            ),
          ],
        );

        final control = find.text('Open in qBittorrent');
        expect(control, findsOneWidget);

        // Never `Semantics(enabled: false)` and never absent: hiding the
        // control would hide the fact with it, and the fact is what the page is
        // for. It is still pressable, it still says why it will not work, and
        // it still keeps a real target.
        final button = find
            .ancestor(of: control, matching: find.byType(TextButton))
            .first;
        expect(tester.widget<TextButton>(button).onPressed, isNotNull);
        expect(
          tester.getSemantics(button).hint,
          contains('requires qBittorrent'),
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      },
    );

    // APP-04: a blocked import was filed as a stall, "Open in qBittorrent",
    // and eighteen of them were eighteen rows.
    testWidgets('blocked imports are one row that offers a manual import', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        screen: const Scaffold(body: ProvidedDecisionRows()),
        decisions: groupDecisions([
          for (var i = 0; i < 18; i++)
            _blocked('Episode $i', at: DateTime.utc(2024, 1, i + 1)),
        ]),
      );

      expect(find.text('18 need a manual import'), findsOneWidget);
      expect(find.text('Manual import'), findsOneWidget);
      expect(find.textContaining('Open in'), findsNothing);
      expect(find.byType(DecisionRow), findsOneWidget);
    });

    testWidgets('manual import opens the Review on the record\'s connection', (
      tester,
    ) async {
      Uri? opened;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const Scaffold(body: ProvidedDecisionRows()),
          ),
          GoRoute(
            path: '/import/blocked',
            builder: (context, state) {
              opened = state.uri;
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await _pumpPage(
        tester,
        _Page.home,
        router: router,
        decisions: [
          _blocked(
            'Dune: Part Two',
            at: DateTime.utc(2024),
            actionId: 12,
            instanceId: 'radarr-hd',
          ),
        ],
      );

      await tester.tap(find.text('Manual import'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      // The Review reads every blocked download of the connection by the
      // client's id for it: no folder and no title to seed. The `?i=` the
      // import routes accept: the files go into the library the record came
      // off, not into whichever one the lens is on.
      expect(opened!.queryParameters, {'service': 'radarr', 'i': 'radarr-hd'});
    });
  });

  group('the stack', () {
    testWidgets('a card carries both figures on arrival: there is no fold', (
      tester,
    ) async {
      await _pumpPage(tester, _Page.stack);

      // Primary and secondary, each present without anything being expanded
      // first. This is the test the fold suite became.
      expect(find.textContaining('2 038'), findsOneWidget);
      expect(find.textContaining('34'), findsOneWidget);
    });

    testWidgets('nothing on the page persists a density', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await _pumpPage(tester, _Page.stack, prefs: prefs);

      // The two keys the fold used to write. A page that still wrote either
      // would be a page that still has a fold.
      expect(prefs.getStringList('services_expanded_domains'), isNull);
      expect(prefs.getInt('services_more_services_dismissed_at'), isNull);
    });

    testWidgets('an answering service has no pip; a dark one does', (
      tester,
    ) async {
      await _pumpPage(tester, _Page.stack);

      // Radarr answers and is proved by its figure.
      expect(_pipsIn(tester, 'service-matrix-cell-radarr'), 0);
      // Lidarr does not answer, and says so twice: the mark and the word.
      expect(_pipsIn(tester, 'service-matrix-cell-lidarr'), 1);
      expect(find.text('Did not answer'), findsOneWidget);
    });

    testWidgets('a checking pip is not amber', (tester) async {
      await _pumpPage(
        tester,
        _Page.stack,
        instanceSummaryFuture: (_) => Completer<ServiceSummary>().future,
        summaryFuture: (_) => Completer<ServiceSummary>().future,
      );

      final context = tester.element(find.text('Radarr'));
      final scheme = Theme.of(context).colorScheme;
      final pip = _pipColour(tester, 'service-matrix-cell-radarr');
      expect(pip, statusToneColor(scheme, StatusTone.neutral));
      expect(pip, isNot(statusToneColor(scheme, StatusTone.warning)));
    });

    testWidgets('an unconfigured service is a cell, not a footnote', (
      tester,
    ) async {
      await _pumpPage(tester, _Page.stack);

      expect(
        find.byKey(const ValueKey('service-matrix-cell-readarr')),
        findsOneWidget,
      );
      expect(find.text(servicesNotSetUpCellLabel), findsWidgets);
    });

    testWidgets('a not-set-up cell opens that service setup form', (
      tester,
    ) async {
      // The same place every `Set up X` goes. It opened the connections list,
      // where the user had to find the service they had just tapped.
      Uri? opened;
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const StackScreen()),
          GoRoute(
            path: '/settings/service/:service',
            builder: (context, state) {
              opened = state.uri;
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await _pumpPage(tester, _Page.stack, router: router);
      final cell = find.byKey(const ValueKey('service-matrix-cell-readarr'));
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await tester.pumpAndSettle();

      expect(opened?.path, ServiceRoutes.setUp(ServiceKey.readarr));
    });

    testWidgets('the region header counts the whole registry', (tester) async {
      await _pumpPage(tester, _Page.stack);

      // The matrix's own header: the app bar above it says Stack too.
      expect(
        find.descendant(
          of: find.byType(ServiceMatrix),
          matching: find.text('Stack'),
        ),
        findsOneWidget,
      );
      expect(find.text('· ${ServiceKey.values.length}'), findsOneWidget);
    });

    testWidgets('a card is one labelled button, not four fragments', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPage(tester, _Page.stack);

      final node = tester.getSemantics(
        find.byKey(const ValueKey('service-matrix-cell-radarr')),
      );
      expect(node.label, 'Radarr');
      // Both figures reach the ear, in a sentence rather than in the cell's
      // visual order.
      expect(node.value, contains('Movies 2 038'));
      expect(node.value, contains('Missing 34'));
      handle.dispose();
    });
  });

  group('downloads', () {
    testWidgets('a stalled transfer is not moving, and says where it went', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        queue: [
          _queueItem('Dune: Part Two', progress: 0.92),
          _queueItem('The Zone of Interest', progress: 0.4, stalled: true),
        ],
        // The same stall, read by Needs you as the decision it is. Every
        // service answering, so that no silence leads it instead.
        instanceSummary: (key) => _summary(key.service, online: true),
        summary: (service) => _summary(service, online: true),
        decisions: [_stall('The Zone of Interest', at: DateTime.utc(2024))],
      );

      await _scrollTo(tester, find.text('Downloads'));

      // What moves says how far it got and how long it has left.
      expect(find.text('Dune: Part Two'), findsOneWidget);
      expect(find.text('92% · 3\u00A0min'), findsOneWidget);
      // What stopped is a row too, saying where, and in amber: a fault. A
      // transfer no arr asked for has nothing to search again, so its
      // remedy is Needs you's: qBittorrent asks the trackers again.
      expect(find.text('The Zone of Interest'), findsOneWidget);
      expect(find.text('Stuck at 40%'), findsOneWidget);
      expect(find.text('Look for peers again'), findsOneWidget);
      final context = tester.element(find.text('Stuck at 40%'));
      expect(
        tester.widget<Text>(find.text('Stuck at 40%')).style?.color,
        statusToneColor(
          Theme.of(context).colorScheme,
          StatusTone.warning,
          surface: CupolaRoom.of(context).slab,
        ),
      );
      // It is not moving: the line counts it apart from what is.
      expect(find.text('1 moving · 1 stuck'), findsOneWidget);
      expect(find.textContaining('2 moving'), findsNothing);
      // And it is still a decision: Needs you leads with it.
      expect(find.text('The Zone of Interest is stuck'), findsOneWidget);
    });

    // APP-01: the line counted the capped preview and printed it as the
    // total.
    testWidgets('the line counts every transfer, not the four it shows', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        queue: [
          for (var i = 0; i < 8; i++)
            _queueItem('Release $i', progress: (8 - i) / 10),
        ],
      );

      await _scrollTo(tester, find.text('Downloads'));

      expect(find.text('8 moving'), findsOneWidget);
      expect(find.textContaining('4 moving'), findsNothing);
      // The rows stay capped.
      expect(find.text('Release 3'), findsOneWidget);
      expect(find.text('Release 4'), findsNothing);
    });

    // APP-04: eighteen blocked imports and nothing downloading read "The queue
    // is empty" over a footnote counting eighteen stalls.
    testWidgets('blocked imports are not an empty queue, and are not stalls', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        // Every source answering: a dark one replaces the empty label with its
        // own message, which is not what is under test.
        instanceSummary: (key) => _summary(key.service, online: true),
        summary: (service) => _summary(service, online: true),
        queue: [
          for (var i = 0; i < 18; i++)
            _queueItem(
              'Blocked $i',
              progress: 1,
              fault: InFlightFault.needsImport,
            ),
        ],
      );

      await _scrollTo(tester, find.text('Downloads'));

      // Nothing is downloading, which is true of a finished download an arr
      // will not import, and the queue is never called empty over them.
      expect(find.textContaining('empty'), findsNothing);
      expect(find.text('Nothing is downloading'), findsOneWidget);
      expect(find.text('Nothing moving'), findsOneWidget);
      expect(
        find.text('18 need a manual import · in Needs you'),
        findsOneWidget,
      );
      expect(find.textContaining('stall'), findsNothing);
    });

    testWidgets('a figure the source did not report reads nothing, never 0', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        queue: [
          const ServiceQueueItem(
            service: ServiceKey.sabnzbd,
            id: 'nothing-known',
            title: 'Nothing.Known.2024',
            progress: null,
            clientLabel: 'SABnzbd',
          ),
          const ServiceQueueItem(
            service: ServiceKey.sabnzbd,
            id: 'half-known',
            title: 'Half.Known.2024',
            progress: 0.1,
            clientLabel: 'SABnzbd',
          ),
        ],
      );

      await _scrollTo(tester, find.text('Downloads'));

      Finder inRow(String title, Finder matching) => find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(DownloadRow),
        ),
        matching: matching,
      );
      // A transfer nothing was reported of has no percent and no bar: `0%`
      // would say it has not started.
      expect(
        inRow('Nothing.Known.2024', find.textContaining('%')),
        findsNothing,
      );
      expect(
        inRow('Nothing.Known.2024', find.byType(HomeRowBar)),
        findsNothing,
      );
      // One half known is one half said: no time left is made up for it.
      expect(inRow('Half.Known.2024', find.text('10%')), findsOneWidget);
      expect(inRow('Half.Known.2024', find.byType(HomeRowBar)), findsOneWidget);
    });

    testWidgets('a speed the client did not report reads —, never 0', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        settings: _settingsWithClient,
        queue: [_queueItem('One', progress: 0.5)],
        // qBittorrent is set up and did not answer: the rate is not known,
        // and what the arr reported is not a rate.
        queueCoverage: SourceCoverage.merge([
          SourceCoverage.answeredBy(ServiceKey.radarr),
          SourceCoverage.failure(
            ServiceKey.qbittorrent,
            const SocketException('Connection refused'),
          ),
        ]),
      );

      await _scrollTo(tester, find.text('Downloads'));

      expect(find.text('1 moving · —'), findsOneWidget);
      expect(find.textContaining('B/s'), findsNothing);
    });

    testWidgets('the line sums the rate once per client', (tester) async {
      await _pumpPage(
        tester,
        _Page.home,
        settings: _settingsWithClient,
        queue: [
          _queueItem('One', progress: 0.5, rate: 1024 * 1024),
          _queueItem('Two', progress: 0.3, rate: 1024 * 1024),
        ],
      );

      await _scrollTo(tester, find.text('Downloads'));

      // Both rows belong to the same client, which reported 1 MB/s for its whole
      // queue, not 2.
      expect(find.text('2 moving · 1.0\u00A0MB/s'), findsOneWidget);
    });
  });

  group('arrived', () {
    testWidgets('names how many titles landed in the week, and counts a '
        'movie imported twice once', (tester) async {
      await _pumpPage(
        tester,
        _Page.home,
        arrivals: [
          _imported('Poor Things', ago: const Duration(hours: 2)),
          // The same movie again, a day earlier: one title.
          _imported('Poor Things', ago: const Duration(hours: 26)),
          _imported('Nickel Boys', ago: const Duration(hours: 5), id: 2),
          // Last week's: not in the week.
          _imported('Old Movie', ago: const Duration(days: 9), id: 3),
        ],
      );

      await _scrollTo(tester, find.text('Arrived'));
      expect(find.text('Last 7 days · 2 new'), findsOneWidget);
      // A failed import is Needs you's, and Arrived says nothing of it.
      expect(find.textContaining('failed'), findsNothing);
    });

    testWidgets('each card is one button whose name is the title, then when '
        'and where', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpPage(
        tester,
        _Page.home,
        arrivals: [
          _imported('Poor Things', ago: const Duration(hours: 2)),
          _imported(
            'Nickel Boys',
            ago: const Duration(hours: 5),
            id: 2,
            connectionName: '4K',
          ),
        ],
      );
      await _scrollTo(tester, find.text('Arrived'));

      // A service with one connection names none; one with two does.
      expect(
        find.bySemanticsLabel('Poor Things, 2\u00A0h ago'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Nickel Boys, 5\u00A0h ago, Radarr 4K'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  testWidgets('pull-to-refresh holds the indicator until the data is back', (
    tester,
  ) async {
    final gate = Completer<List<ArrHistoryEntry>>();
    await _pumpPage(tester, _Page.home, arrivalsFuture: () => gate.future);

    // The page's own list, the first in the tree: the Home is short enough now
    // for Arrived's rail, a list of its own, to be built beside it.
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    gate.complete(const []);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

typedef _InstanceKey = ({ServiceKey service, String instanceId});

/// The two pages the old Dashboard became.
enum _Page { home, stack }

Widget _screen(_Page page) => switch (page) {
  _Page.home => const HomeScreen(),
  _Page.stack => const StackScreen(),
};

/// The runtime types of the regions [page] lays out, top to bottom, read off its
/// list view.
List<String> _regionsOnPage(WidgetTester tester) {
  final list = tester.widget<ListView>(find.byType(ListView));
  final children = (list.childrenDelegate as SliverChildListDelegate).children;
  // Wider than the reading well, the Home sets each module in its column.
  Widget region(Widget child) =>
      child is Padding && child.child != null ? child.child! : child;
  return [for (final child in children) region(child).runtimeType.toString()];
}

/// Pumps [page] with every source overridden.
///
/// Nothing here reaches a network: the four providers the page reads are handed
/// values, and `instanceSummaryProvider` is overridden as well as
/// `serviceSummaryProvider` because the header counts **connections**, so a
/// fixture that only answers the per-service probe would leave it saying
/// "checking" forever.
Future<void> _pumpPage(
  WidgetTester tester,
  _Page page, {
  SettingsModel? settings,
  List<DashboardDecision>? decisions,
  SourceCoverage decisionsCoverage = SourceCoverage.none,
  List<ServiceQueueItem>? queue,
  SourceCoverage queueCoverage = SourceCoverage.none,
  List<ArrHistoryEntry>? arrivals,
  SourceCoverage arrivalsCoverage = SourceCoverage.none,
  Future<List<ArrHistoryEntry>> Function()? arrivalsFuture,
  ServiceSummary Function(_InstanceKey key)? instanceSummary,
  Future<ServiceSummary> Function(_InstanceKey key)? instanceSummaryFuture,
  ServiceSummary Function(ServiceKey service)? summary,
  Future<ServiceSummary> Function(ServiceKey service)? summaryFuture,
  Future<ServiceSignalPair?> Function(ServiceKey service)? signalPairFuture,
  SharedPreferences? prefs,
  GoRouter? router,

  /// What to draw in the page's place: a widget of a test's own.
  Widget? screen,
}) async {
  final overrides = <Override>[
    if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
    // The Home reads who the shell is drawn for, which waits on onboarding.
    initialOnboardingCompletedProvider.overrideWithValue(true),
    currentSettingsProvider.overrideWith((ref) => settings ?? _settings),
    instanceSummaryProvider.overrideWith(
      (ref, key) =>
          instanceSummaryFuture?.call(key) ??
          Future.value(instanceSummary?.call(key) ?? _summary(key.service)),
    ),
    serviceSummaryProvider.overrideWith(
      (ref, service) =>
          summaryFuture?.call(service) ??
          Future.value(summary?.call(service) ?? _summary(service)),
    ),
    serviceSignalPairProvider.overrideWith(
      (ref, service) async =>
          await signalPairFuture?.call(service) ??
          switch (service) {
            ServiceKey.radarr => const ServiceSignalPair(
              primary: ServiceSignal(
                label: 'movies',
                value: '2 038',
                icon: Icons.movie_rounded,
                tone: StatusTone.neutral,
              ),
              secondary: ServiceSignal(
                label: 'missing',
                value: '34',
                icon: Icons.report_gmailerrorred_rounded,
                tone: StatusTone.neutral,
              ),
            ),
            ServiceKey.seerr => const ServiceSignalPair(
              primary: ServiceSignal(
                label: 'pending',
                value: '4',
                icon: Icons.hourglass_top_rounded,
                tone: StatusTone.neutral,
              ),
            ),
            _ => null,
          },
    ),
    dashboardDecisionsProvider.overrideWithValue((
      decisions: rankDecisions(decisions ?? const []),
      coverage: decisionsCoverage,
    )),
    // Requests reads its own source and not the folded list: the requests
    // among [decisions] are what that source holds.
    dashboardDecisionSourceProvider.overrideWith(
      (ref, source) async => (
        decisions: [
          if (source == DecisionSource.requests)
            for (final decision in rankDecisions(decisions ?? const []))
              if (decision.kind == DecisionKind.pendingRequest) decision,
        ],
        coverage: decisionsCoverage,
      ),
    ),
    servicesQueueProvider.overrideWith(
      (ref) async => (items: queue ?? const [], coverage: queueCoverage),
    ),
    servicesArrHistoryProvider.overrideWith(
      (ref) async =>
          (entries: const <ArrHistoryEntry>[], coverage: SourceCoverage.none),
    ),
    // Arrived's week is read against a clock of the test's own, so a card's
    // age is not the day the suite runs on.
    arrivalsClockProvider.overrideWithValue(() => _arrivalsNow),
    servicesArrivalsProvider.overrideWith(
      (ref) async => (
        entries:
            await (arrivalsFuture?.call() ??
                Future.value(arrivals ?? const <ArrHistoryEntry>[])),
        coverage: arrivalsCoverage,
      ),
    ),
    // Nothing is coming up and nothing is in progress: the two reads the
    // Home makes beside the others are handed an answer and never reach a
    // network.
    libraryCalendarProvider.overrideWith(
      (ref) async => LibraryCalendar(
        window: CalendarWindow.from(_arrivalsNow),
        events: const [],
        answered: const ['Radarr'],
        silent: const [],
        kinds: const {},
        readAt: _arrivalsNow,
      ),
    ),
    homeResumeProvider.overrideWith(
      (ref) async => (
        rows: const <ResumeRow>[],
        coverage: SourceCoverage.none,
        viewerMissing: const <String>[],
      ),
    ),
    servicesRequestsProvider.overrideWith(
      (ref) async => const <SeerrRequest>[],
    ),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: router == null
          ? MaterialApp(home: screen ?? _screen(page))
          : MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  // Featured holds its place until its sources answer, then steps aside: the
  // modules it held below the fold are built on this frame, and their reads
  // settle as the earlier ones did.
  await tester.pump(const Duration(milliseconds: 50));
}

/// Seerr, Radarr and Sonarr answer; Lidarr is the configured service that does
/// not, so the fixture exercises the alert band and a drained card at once.
final SettingsModel _settings = settingsWith(
  seerrUrl: 'http://seerr.local:5055',
  seerrApiKey: 'key',
  radarrUrl: 'http://radarr.local:7878',
  radarrApiKey: 'key',
  sonarrUrl: 'http://sonarr.local:8989',
  sonarrApiKey: 'key',
  lidarrUrl: 'http://lidarr.local:8686',
  lidarrApiKey: 'key',
);

/// [_settings] with a download client set up: the speed on Downloads is the
/// client's to say.
final SettingsModel _settingsWithClient = settingsWith(
  seerrUrl: 'http://seerr.local:5055',
  seerrApiKey: 'key',
  radarrUrl: 'http://radarr.local:7878',
  radarrApiKey: 'key',
  sonarrUrl: 'http://sonarr.local:8989',
  sonarrApiKey: 'key',
  lidarrUrl: 'http://lidarr.local:8686',
  lidarrApiKey: 'key',
  qbittorrentUrl: 'http://qbittorrent.local:8080',
  qbittorrentUsername: 'user',
  qbittorrentPassword: 'pass',
);

/// One service, two connections: the shape the header's `degraded` exists for.
final SettingsModel _twoRadarrSettings = settingsWith(
  instances: const [
    ServiceInstance(
      id: 'radarr-4k',
      service: ServiceKey.radarr,
      label: '4K',
      url: 'http://radarr-4k.local:7878',
      credential: 'key',
    ),
    ServiceInstance(
      id: 'radarr-hd',
      service: ServiceKey.radarr,
      label: 'HD',
      url: 'http://radarr-hd.local:7878',
      credential: 'key',
    ),
  ],
);

ServiceSummary _summary(ServiceKey service, {bool? online}) {
  const hosts = {
    ServiceKey.seerr: 'seerr.local:5055',
    ServiceKey.radarr: 'radarr.local:7878',
    ServiceKey.sonarr: 'sonarr.local:8989',
    ServiceKey.lidarr: 'lidarr.local:8686',
  };

  final isUp =
      online ??
      const {
        ServiceKey.seerr,
        ServiceKey.radarr,
        ServiceKey.sonarr,
      }.contains(service);

  return ServiceSummary(
    service: service,
    status: isUp ? ServiceSummaryStatus.online : ServiceSummaryStatus.offline,
    host: hosts[service] ?? '',
    version: isUp ? '1.0.0' : null,
  );
}

DashboardDecision _stall(
  String title, {
  required DateTime at,
  ServiceKey? requires,
}) => DashboardDecision(
  kind: DecisionKind.stalledDownload,
  id: 'stall-$title',
  service: ServiceKey.radarr,
  title: title,
  detail: 'Stalled · Radarr',
  occurredAt: at,
  requiresService: requires,
);

DashboardDecision _blocked(
  String title, {
  required DateTime at,
  int? actionId,
  String instanceId = '',
}) => DashboardDecision(
  kind: DecisionKind.importBlocked,
  id: 'blocked-$title',
  service: ServiceKey.radarr,
  title: title,
  detail: 'Import blocked · Radarr',
  occurredAt: at,
  actionId: actionId,
  instanceId: instanceId,
);

DashboardDecision _request(String title, {required DateTime at}) =>
    DashboardDecision(
      kind: DecisionKind.pendingRequest,
      id: 'request-$title',
      service: ServiceKey.seerr,
      title: title,
      detail: 'Seerr · nadia',
      occurredAt: at,
      actionId: 1,
    );

ServiceQueueItem _queueItem(
  String title, {
  required double progress,
  bool stalled = false,
  InFlightFault? fault,
  int? rate,
}) => ServiceQueueItem(
  service: ServiceKey.qbittorrent,
  id: title,
  title: title,
  progress: progress,
  quality: '2160p',
  doneBytes: 14 * 1024 * 1024 * 1024,
  totalBytes: 15 * 1024 * 1024 * 1024,
  etaSeconds: 180,
  clientLabel: 'qBittorrent',
  clientService: ServiceKey.qbittorrent,
  clientRateBytesPerSecond: rate,
  fault: fault ?? (stalled ? InFlightFault.stalled : null),
  stalledSince: stalled || fault != null ? DateTime.utc(2024, 1, 1) : null,
);

/// The moment Arrived's week is read from in these tests.
final DateTime _arrivalsNow = DateTime.utc(2024, 5, 5, 10, 12);

/// One import of a movie, [ago] before [_arrivalsNow].
ArrHistoryEntry _imported(
  String title, {
  required Duration ago,
  int id = 1,
  String? connectionName,
}) => ArrHistoryEntry(
  service: ServiceKey.radarr,
  id: id,
  mediaId: id,
  title: title,
  unitId: null,
  detail: null,
  posterUrl: '',
  outcome: ArrImportOutcome.imported,
  at: _arrivalsNow.subtract(ago),
  reason: null,
  connectionName: connectionName,
);

double _yOf(WidgetTester tester, Finder finder) =>
    tester.getTopLeft(finder.first).dy;

String _textContaining(WidgetTester tester, String needle) {
  final widget = tester
      .widgetList<Text>(find.byType(Text))
      .firstWhere((text) => (text.data ?? '').contains(needle));
  return widget.data!;
}

/// How many reachability pips one card is drawing.
///
/// Matched on the shape rather than on a type: the pip is private to
/// `service_matrix.dart` on purpose: it is the anatomy of one screen, not a
/// reusable component.
int _pipsIn(WidgetTester tester, String cellKey) => find
    .descendant(
      of: find.byKey(ValueKey(cellKey)),
      matching: find.byWidgetPredicate(_isPip),
    )
    .evaluate()
    .length;

Color _pipColour(WidgetTester tester, String cellKey) {
  final pip = tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(ValueKey(cellKey)),
          matching: find.byWidgetPredicate(_isPip),
        )
        .first,
  );
  return ((pip.decoration! as BoxDecoration).color)!;
}

bool _isPip(Widget widget) =>
    widget is Container &&
    widget.decoration is BoxDecoration &&
    (widget.decoration! as BoxDecoration).shape == BoxShape.circle;

Future<void> _scrollTo(WidgetTester tester, Finder target) {
  return tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
  );
}
