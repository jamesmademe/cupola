import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/search/presentation/search_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';

import '../../../test_helpers/settings_scope.dart';

/// The lane is the unit this screen is built out of: one connection, its own
/// state, its own Retry. Everything here guards a rule about that unit rather
/// than a rendering of it — the resolved tone, the word off the enum, which
/// lane a Retry touches.
void main() {
  testWidgets('a lane still out does not hold the lane that answered', (
    tester,
  ) async {
    // The promise the whole per-leg model exists to keep. Under the single
    // `Future.wait` this replaced, one parked server meant a page-wide skeleton
    // and no rows at all.
    final bazarr = _ParkedBazarrService();
    await _pump(tester, bazarr: bazarr);

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Searching…'), findsOneWidget);
    expect(find.byType(ShimmerPlaceholder), findsWidgets);

    await _release(tester, bazarr.release);
  });

  testWidgets('"no results anywhere" waits for every lane to answer', (
    tester,
  ) async {
    // A page that says "no results" while a lane is still out is a page that
    // contradicts itself two seconds later.
    final bazarr = _ParkedBazarrService();
    await _pump(
      tester,
      radarr: _LaneRadarrService(results: const []),
      bazarr: bazarr,
    );

    expect(find.text('No results'), findsNothing);
    expect(find.text('Searching…'), findsOneWidget);

    await _release(tester, bazarr.release);
  });

  testWidgets('a lane past its deadline is amber and says why once', (
    tester,
  ) async {
    // TONE: a slow server is a fault, so the lane is amber — never the red
    // the old code painted every failure, which made a Bazarr taking nine
    // seconds read exactly like a Bazarr that was unplugged. The card says
    // why; the heading above it no longer says it again.
    await _pump(tester, radarr: _LaneRadarrService(parks: true));
    await _passTheDeadline(tester);

    expect(
      find.text('No Radarr results: the search timed out.'),
      findsOneWidget,
    );
    expect(find.text('Did not answer in time'), findsNothing);

    final context = tester.element(find.byType(SearchScreen));
    final colorScheme = Theme.of(context).colorScheme;
    final glyph = tester.widget<Icon>(find.byIcon(Icons.timer_off_rounded));
    expect(
      glyph.color,
      statusToneColor(colorScheme, StatusTone.warning),
      reason: 'the tone comes from the vocabulary, never from a literal',
    );
    // And not the red arm, which is reserved for a connection nothing answered
    // at.
    expect(glyph.color, isNot(statusToneColor(colorScheme, StatusTone.error)));
  });

  testWidgets('Retry names the connection it will ask again', (tester) async {
    // Up to seven of these on one screen: a screen reader hearing "Retry" seven
    // times cannot tell which server it is about to wake.
    await _pump(tester, radarr: _LaneRadarrService(parks: true));
    await _passTheDeadline(tester);

    expect(find.bySemanticsLabel('Retry Radarr'), findsOneWidget);
  });

  testWidgets('Retry puts that lane back in flight and nothing else', (
    tester,
  ) async {
    final radarr = _LaneRadarrService(parks: true);
    await _pump(tester, radarr: radarr);
    await _passTheDeadline(tester);
    expect(radarr.calls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    // The lane the user pressed asked again; the Seerr lane beside it kept the
    // answer it already had.
    expect(radarr.calls, 2);
    expect(find.text('Searching…'), findsOneWidget);
    expect(find.text('Did not answer in time'), findsNothing);
    expect(find.text('No Seerr results'), findsOneWidget);

    await _release(tester, radarr.release);
  });

  testWidgets('the refresh command re-runs the query instead of erasing it', (
    tester,
  ) async {
    // ⌘R and re-tapping the Search tab are opposite commands, and they used to
    // share one channel whose only listener cleared the field — so the window's
    // Refresh silently threw the user's query away.
    final radarr = _LaneRadarrService(
      results: [buildMovie(id: 10, title: 'Dune', year: 2024)],
    );
    await _pump(tester, radarr: radarr);
    expect(radarr.calls, 1);

    final container = _containerOf(tester);
    container.read(globalSearchRerunProvider.notifier).state++;
    await tester.pump();
    await tester.pump();

    expect(radarr.calls, 2);
    expect(container.read(globalSearchQueryProvider), 'dune');
  });

  testWidgets('re-tapping the tab clears the filter along with the field', (
    tester,
  ) async {
    // "Give me a clean field" has to mean a clean screen: a one-service filter
    // that survived the clear applied itself to the next query, and on a
    // service whose connection had gone it left nothing on screen at all.
    await _pump(tester);
    final container = _containerOf(tester);

    await tester.tap(find.text('Radarr').first);
    await tester.pump();
    expect(find.text('No Seerr results'), findsNothing);

    container
        .read(navigationRefreshProvider(NavigationSection.search).notifier)
        .state++;
    await tester.pump();
    expect(container.read(globalSearchQueryProvider), isEmpty);

    container.read(globalSearchQueryProvider.notifier).state = 'dune';
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('No Seerr results'), findsOneWidget);
  });

  testWidgets('the field is monochrome: the magnifier is the secondary ink', (
    tester,
  ) async {
    // It used to take the Search section's own purple, handed over explicitly;
    // the chrome has no section colours now, so the field draws the same
    // secondary-ink magnifier it draws on every other screen.
    await _pump(tester);

    final context = tester.element(find.byType(SearchScreen));
    final colorScheme = Theme.of(context).colorScheme;
    final glyph = tester.widget<Icon>(
      find.descendant(
        of: find.byType(SearchBarHeader),
        matching: find.byIcon(Icons.search_rounded),
      ),
    );
    expect(glyph.color, colorScheme.onSurfaceVariant);
  });

  testWidgets('the filter strip offers only services that can answer', (
    tester,
  ) async {
    // Selecting a chip for an unconfigured service produced no lanes, no
    // results and — because the empty state was gated on there being no filter
    // — no empty state either. A literally blank screen.
    await _pump(tester);

    expect(find.text('All services'), findsOneWidget);
    expect(find.text('Radarr'), findsWidgets);
    expect(find.text('Sonarr'), findsNothing);
    expect(find.text('Lidarr'), findsNothing);
  });
}

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SearchScreen)));

/// Lets the lane's own deadline pass and the rebuild land.
///
/// `flutter_test` drives timers off a fake clock, so this costs nothing in real
/// time and exercises the same `Future.timeout` the app runs.
Future<void> _passTheDeadline(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await tester.pump();
}

/// Lets a parked leg finish before the tree comes down.
///
/// A leg that is still out holds its own deadline timer, and `flutter_test`
/// fails a test that leaves one pending. In the app the token's cancellation
/// completes the request and the timer goes with it; a fake has to be told.
Future<void> _release(WidgetTester tester, void Function() release) async {
  release();
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester, {
  RadarrService? radarr,
  BazarrService? bazarr,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          // Three connections, because "nothing blocks" needs more than one
          // lane to mean anything.
          (ref) => settingsWith(
            radarrUrl: 'http://radarr.local:7878',
            radarrApiKey: 'key',
            seerrUrl: 'http://seerr.local:5055',
            seerrApiKey: 'key',
            bazarrUrl: 'http://bazarr.local:6767',
            bazarrApiKey: 'key',
          ),
        ),
        globalSearchQueryProvider.overrideWith((ref) => 'dune'),
        seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
        bazarrServiceProvider.overrideWithValue(bazarr ?? FakeBazarrService()),
        radarrServiceProvider.overrideWith(
          (ref) =>
              radarr ??
              _LaneRadarrService(
                results: [buildMovie(id: 10, title: 'Dune', year: 2024)],
              ),
        ),
      ],
      child: const MaterialApp(home: SearchScreen()),
    ),
  );
  // Discrete pumps rather than `pumpAndSettle`: a lane that is still out draws
  // a shimmer whose controller repeats forever.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class _LaneRadarrService extends FakeRadarrService {
  _LaneRadarrService({this.results = const [], this.parks = false});

  final List<RadarrMovie> results;

  /// Never answers, for the lane that has to reach its own deadline.
  final bool parks;

  final List<Completer<List<RadarrMovie>>> _parked = [];

  var calls = 0;

  @override
  Future<List<RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) {
    calls++;
    if (!parks) return Future.value(results);
    final completer = Completer<List<RadarrMovie>>();
    _parked.add(completer);
    return completer.future;
  }

  void release() {
    for (final completer in _parked) {
      if (!completer.isCompleted) completer.complete(results);
    }
  }
}

class _ParkedBazarrService extends FakeBazarrService {
  final List<Completer<List<BazarrSearchHit>>> _parked = [];

  @override
  Future<List<BazarrSearchHit>> searchLibrary(
    String query, {
    int length = 500,
    CancelToken? cancelToken,
  }) {
    final completer = Completer<List<BazarrSearchHit>>();
    _parked.add(completer);
    return completer.future;
  }

  void release() {
    for (final completer in _parked) {
      if (!completer.isCompleted) completer.complete(const []);
    }
  }
}
