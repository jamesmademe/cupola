/// The Home and the Stack, region by region.
///
/// Every test here guards a **rule**, not a rendering: the order of the regions
/// on each page, the ranking inside the decisions list, the cap per size class,
/// that a probe still out is not a fault, that a figure nobody could take reads
/// `—` and not `0`, and that a control whose target is not configured is dimmed
/// but still reachable. Nothing asserts a hex or a pixel — those are the
/// canvas's to change and this file's to survive.
///
/// The page that was the Dashboard is two now. The Home keeps what needs a
/// decision, what is in flight and what was recently added, under the band; the
/// Stack keeps the headline, the band and the matrix of services. The band and
/// the empty state are on both, so their tests run on both.
///
/// The fold tests that used to fill most of this file are gone, and the two that
/// replace them are the reason they are gone rather than deleted: the stack now
/// has **one density**, so a card carries its figures on arrival and there is no
/// persisted preference, no demo and no per-domain toggle to restore.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/recently_added.dart';
import 'package:cupola/features/services/domain/service_signal.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/service_matrix.dart';
import 'package:cupola/features/services/presentation/services_alert_band.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets("the Home's regions are in the settled order", (tester) async {
    await _pumpPage(
      tester,
      _Page.home,
      decisions: [_stall('Furiosa', at: DateTime.utc(2024))],
    );

    // Read off the list rather than off the screen: the regions below the band
    // are built lazily, so a y-coordinate comparison would be testing the
    // viewport height. Three questions, in this order — is everything all right
    // → what needs me → what is moving — and what arrived last.
    expect(_regionsOnPage(tester), [
      'ServicesAlertBand',
      'DashboardDecisionsSection',
      'ServicesInFlightSection',
      'ServicesRecentlyAddedSection',
    ]);
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
      // The front door after "Skip for now", on the first tab and on the
      // Stack alike. Its button used to borrow the pick step's title while
      // opening Connections, which sets up one service at a time, and its
      // headline used the word for a service that stayed silent.
      testWidgets('says nothing is set up and opens Connections', (
        tester,
      ) async {
        String? opened;
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (context, state) => _screen(page)),
            GoRoute(
              path: ServiceRoutes.settingsConnections,
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

        await tester.tap(find.text('Set up a service'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(opened, ServiceRoutes.settingsConnections);
      });
    });
  }

  group('the header', () {
    testWidgets('counts connections folded per service, and says degraded', (
      tester,
    ) async {
      // Two Radarr, one of them dark: the service still answers, so it is not
      // unreachable — it is degraded, and the sum still closes over the
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

  // The band is on both pages: what stopped answering is the first thing
  // either one says.
  for (final page in _Page.values) {
    group('the alert band, the ${page.name}', () {
      testWidgets('names the offenders in the settled words', (tester) async {
        await _pumpPage(tester, page);

        // Lidarr is the configured service that does not answer in the fixture.
        // Scoped to the band: the same sentence is what a region whose sources are
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
        // One offender, so the bare verb — `Retry both` is for exactly two.
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

        // The header is the Stack's; the Home has the band and no header, and
        // the band must stay silent there all the same.
        if (page == _Page.stack) {
          expect(find.textContaining('1 degraded'), findsOneWidget);
        }
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
  }

  group('needs a decision', () {
    testWidgets('faults come before backlog, oldest first inside a kind', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        decisions: [
          _request('Severance', at: DateTime.utc(2024, 1, 1)),
          _stall('The Zone of Interest', at: DateTime.utc(2024, 5, 2)),
          _stall('Fantasia', at: DateTime.utc(2024, 5, 1)),
        ],
      );

      // The request is the oldest item on the list by four months and still
      // sorts last: it is backlog, and backlog never outranks a fault.
      expect(
        _yOf(tester, find.text('Fantasia')),
        lessThan(_yOf(tester, find.text('The Zone of Interest'))),
      );
      expect(
        _yOf(tester, find.text('The Zone of Interest')),
        lessThan(_yOf(tester, find.text('Severance'))),
      );
    });

    testWidgets('the phone shows three, and says how many there are', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        decisions: [
          for (var i = 0; i < 5; i++)
            _stall('Stalled $i', at: DateTime.utc(2024, 1, i + 1)),
        ],
      );

      // Three rows, and the two the cap dropped are simply not built.
      expect(find.text('Stalled 0'), findsOneWidget);
      expect(find.text('Stalled 2'), findsOneWidget);
      expect(find.text('Stalled 3'), findsNothing);
      // The cap hides rows; the header must not hide the count.
      expect(find.text('See all 5 →'), findsOneWidget);
    });

    testWidgets('is absent when nothing is waiting', (tester) async {
      await _pumpPage(tester, _Page.home, decisions: const []);
      expect(find.text('Needs a decision'), findsNothing);
    });

    testWidgets(
      'a control whose target is not configured is dimmed but reachable',
      (tester) async {
        await _pumpPage(
          tester,
          _Page.home,
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

    // APP-04: a blocked import was filed as a stall — "Open in qBittorrent" —
    // and eighteen of them were eighteen rows.
    testWidgets('blocked imports are one row that offers a manual import', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        decisions: groupDecisions([
          for (var i = 0; i < 18; i++)
            _blocked('Episode $i', at: DateTime.utc(2024, 1, i + 1)),
        ]),
      );

      expect(find.text('18 need a manual import'), findsOneWidget);
      expect(find.text('Manual import'), findsOneWidget);
      expect(find.textContaining('Open in'), findsNothing);
      // The cap counts rows; the header counts what they stand for.
      expect(find.text('See all 18 →'), findsOneWidget);
      expect(find.text('18 items · blocked imports'), findsOneWidget);
    });

    testWidgets('manual import opens the wizard on the record\'s connection', (
      tester,
    ) async {
      Uri? opened;
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          GoRoute(
            path: '/import/browse',
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
            importPath: '/downloads/Dune.Part.Two/Dune.Part.Two.mkv',
          ),
        ],
      );

      await tester.tap(find.text('Manual import'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(opened!.queryParameters, {
        'service': 'radarr',
        'targetId': '12',
        'path': '/downloads/Dune.Part.Two',
        // The `?i=` the import routes accept: the files go into the library
        // the record came off, not into whichever one the lens is on.
        'i': 'radarr-hd',
      });
    });

    testWidgets('a pending request keeps both of its decisions', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        decisions: [_request('A Quiet Place', at: DateTime.utc(2024, 1, 1))],
      );

      expect(find.byTooltip('Approve A Quiet Place'), findsOneWidget);
      expect(find.byTooltip('Decline A Quiet Place'), findsOneWidget);
    });
  });

  group('the stack', () {
    testWidgets('a card carries both figures on arrival — there is no fold', (
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

  group('in flight', () {
    testWidgets('a stalled transfer is not in flight, and says where it went', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        queue: [
          _queueItem('Dune: Part Two', progress: 0.92),
          _queueItem('The Zone of Interest', progress: 0.4, stalled: true),
        ],
      );

      await _scrollTo(tester, find.text('In flight'));

      expect(find.text('Dune: Part Two'), findsOneWidget);
      expect(find.text('The Zone of Interest'), findsNothing);
      expect(find.textContaining('1 stuck'), findsOneWidget);
    });

    // APP-01: the eyebrow counted the five-row preview and printed it as the
    // total.
    testWidgets('the eyebrow counts every transfer, not the five it shows', (
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

      await _scrollTo(tester, find.text('In flight'));

      expect(find.textContaining('8 downloading'), findsOneWidget);
      expect(find.textContaining('5 downloading'), findsNothing);
      // The rows stay capped.
      expect(find.text('Release 4'), findsOneWidget);
      expect(find.text('Release 5'), findsNothing);
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

      await _scrollTo(tester, find.text('In flight'));

      expect(find.text('The queue is empty'), findsNothing);
      expect(find.text('Nothing moving'), findsOneWidget);
      expect(
        find.text('18 need a manual import · under Needs a decision'),
        findsOneWidget,
      );
      expect(find.textContaining('stall'), findsNothing);
    });

    testWidgets('a figure the source did not report reads —, never 0', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        queue: [
          const ServiceQueueItem(
            service: ServiceKey.sabnzbd,
            title: 'Nothing.Known.2024',
            progress: 0.1,
            clientLabel: 'SABnzbd',
          ),
        ],
      );

      await _scrollTo(tester, find.text('In flight'));

      // The row's own line, not the stack card that happens to share the name.
      final line = _textContaining(tester, '· SABnzbd');
      expect(line, contains('—'));
      // A count nobody was able to take is not zero, and `0 B` would say the
      // transfer has not started.
      expect(line, isNot(contains('0\u00A0B')));
    });

    testWidgets('the eyebrow sums the rate once per client', (tester) async {
      await _pumpPage(
        tester,
        _Page.home,
        queue: [
          _queueItem('One', progress: 0.5, rate: 1024 * 1024),
          _queueItem('Two', progress: 0.3, rate: 1024 * 1024),
        ],
      );

      await _scrollTo(tester, find.text('In flight'));

      // Both rows belong to the same client, which reported 1 MB/s for its whole
      // queue — not 2.
      expect(
        find.textContaining('1.0\u00A0MB/s across 1 client'),
        findsOneWidget,
      );
    });
  });

  group('recently added', () {
    testWidgets('names how many landed and, in amber, how many did not', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _Page.home,
        recentlyAdded: [
          _imported('Poor Things', at: DateTime.utc(2024, 5, 5, 8, 12)),
          _imported(
            'Nickel Boys',
            at: DateTime.utc(2024, 5, 5, 6, 58),
            failed: true,
          ),
        ],
      );

      await _scrollTo(tester, find.text('Recently added'));
      expect(find.text('1 imported'), findsOneWidget);

      final failed = tester.widget<Text>(find.text('1 failed'));
      final context = tester.element(find.text('1 failed'));
      final scheme = Theme.of(context).colorScheme;
      // Amber, because a failed import is a fault. Red is reserved for a
      // connection that did not answer.
      expect(
        failed.style?.color,
        statusToneColor(scheme, StatusTone.warning, surface: scheme.surface),
      );
    });

    testWidgets('each tile is a target whose name is title, service, time', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPage(
        tester,
        _Page.home,
        recentlyAdded: [
          _imported('Poor Things', at: DateTime.utc(2024, 5, 5, 8, 12)),
        ],
      );
      await _scrollTo(tester, find.text('Recently added'));

      expect(
        find.bySemanticsLabel(RegExp(r'Poor Things, Radarr, \d\d:\d\d')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  testWidgets('pull-to-refresh holds the indicator until the data is back', (
    tester,
  ) async {
    final gate = Completer<List<RecentlyAddedItem>>();
    await _pumpPage(tester, _Page.home, recentlyAddedFuture: () => gate.future);

    // The page's own list, the first in the tree: the Home is short enough now
    // for Recently added's shelf, a list of its own, to be built beside it.
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
  return [for (final child in children) child.runtimeType.toString()];
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
  List<RecentlyAddedItem>? recentlyAdded,
  SourceCoverage recentlyAddedCoverage = SourceCoverage.none,
  Future<List<RecentlyAddedItem>> Function()? recentlyAddedFuture,
  ServiceSummary Function(_InstanceKey key)? instanceSummary,
  Future<ServiceSummary> Function(_InstanceKey key)? instanceSummaryFuture,
  ServiceSummary Function(ServiceKey service)? summary,
  Future<ServiceSummary> Function(ServiceKey service)? summaryFuture,
  Future<ServiceSignalPair?> Function(ServiceKey service)? signalPairFuture,
  SharedPreferences? prefs,
  GoRouter? router,
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
    servicesQueueProvider.overrideWith(
      (ref) async => (items: queue ?? const [], coverage: queueCoverage),
    ),
    servicesArrHistoryProvider.overrideWith(
      (ref) async =>
          (entries: const <ArrHistoryEntry>[], coverage: SourceCoverage.none),
    ),
    servicesRecentlyAddedProvider.overrideWith(
      (ref) async => (
        items:
            await (recentlyAddedFuture?.call() ??
                Future.value(recentlyAdded ?? const <RecentlyAddedItem>[])),
        coverage: recentlyAddedCoverage,
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
          ? MaterialApp(home: _screen(page))
          : MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
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

/// One service, two connections — the shape the header's `degraded` exists for.
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
  String? importPath,
}) => DashboardDecision(
  kind: DecisionKind.importBlocked,
  id: 'blocked-$title',
  service: ServiceKey.radarr,
  title: title,
  detail: 'Import blocked · Radarr',
  occurredAt: at,
  actionId: actionId,
  instanceId: instanceId,
  importPath: importPath,
);

DashboardDecision _request(String title, {required DateTime at}) =>
    DashboardDecision(
      kind: DecisionKind.pendingRequest,
      id: 'request-$title',
      service: ServiceKey.seerr,
      title: title,
      detail: 'Request · nadia',
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

RecentlyAddedItem _imported(
  String title, {
  required DateTime at,
  bool failed = false,
}) => RecentlyAddedItem(
  service: ServiceKey.radarr,
  id: 1,
  title: title,
  posterUrl: '',
  addedAt: at,
  failed: failed,
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
/// `service_matrix.dart` on purpose — it is the anatomy of one screen, not a
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
