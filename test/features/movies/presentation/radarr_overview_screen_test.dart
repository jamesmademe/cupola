import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  testWidgets('draws the regions in the order the board draws them', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(movies: [_movie(id: 1)]));

    // Identity and the readouts come before any section, and only this tab
    // carries them.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Coming up', 'Needs attention', 'Recently added', 'History'],
    );
  });

  testWidgets('each section link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester, service: _scripted());

    final headers = tester
        .widgetList<SectionHeader>(find.byType(SectionHeader))
        .toList();

    expect(headers.map((header) => header.semanticHint), [
      'opens the Radarr Calendar tab',
      // Needs attention has no single destination: its rows belong to
      // different tabs, so it offers no link at all rather than a wrong one.
      null,
      'opens the Radarr Library tab',
      'opens the Radarr History tab',
    ]);
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(), version: '5.4.6');

    expect(
      find.semantics.byLabel('Radarr, radarr.local:7878, v5.4.6, Answering'),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets(
    'an unreachable Radarr reads Did not answer, and its version is —',
    (tester) async {
      await _pump(tester, service: _scripted(), version: null);

      expect(
        find.semantics.byLabel('Radarr, radarr.local:7878, —, Did not answer'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _FailingHistoryRadarr([
        _movie(
          id: 1,
          title: 'Soon',
          digitalRelease: DateTime(
            today.year,
            today.month,
            today.day + 1,
            9,
          ).toIso8601String(),
        ),
      ]),
    );

    // The failed region says so in its own slot…
    expect(find.byType(InlineErrorRetry), findsOneWidget);
    expect(
      find.textContaining(", so today's history is not shown."),
      findsOneWidget,
    );
    // …and the other three still drew.
    expect(find.byType(SectionHeader), findsNWidgets(4));
    expect(find.text('Soon'), findsOneWidget);
    // In the calendar's words, so one date has one name on both screens. It
    // read "digital release" here and "on digital" on the calendar tab.
    expect(find.textContaining('on digital'), findsOneWidget);
    expect(find.textContaining('digital release'), findsNothing);
  });

  testWidgets('a fault row and a backlog row are spoken as sentences', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        queue: [
          {
            'movie': {'title': 'Nickel Boys'},
            'trackedDownloadState': 'importFailed',
            'errorMessage': 'Radarr could not match the file',
          },
        ],
        cutoffTotal: 2,
      ),
    );

    expect(
      find.semantics.byLabel(
        'Import failed, Nickel Boys, Radarr could not match the file',
      ),
      findsOneWidget,
    );
    expect(
      find.semantics.byLabel(
        '2 movies below your quality cutoff, '
        'Radarr keeps searching for an upgrade',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a poster on the recently added rail has an accessible name', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        movies: [
          _movie(
            id: 7,
            title: 'Dune: Part Two',
            added: today.toIso8601String(),
          ),
        ],
      ),
    );

    expect(
      tester.getSemantics(
        find.ancestor(
          of: find.text('Dune: Part Two'),
          matching: find.byType(PressableScale),
        ),
      ),
      isSemantics(label: 'Dune: Part Two', isButton: true),
    );
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      service: _scripted(
        movies: [
          _movie(
            id: 1,
            title: 'A Very Long Film Title That Will Not Fit One Line',
            added: today.toIso8601String(),
            digitalRelease: DateTime(
              today.year,
              today.month,
              today.day + 2,
              9,
            ).toIso8601String(),
          ),
        ],
        cutoffTotal: 1,
      ),
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulling to refresh refetches the library, not just the clock', (
    tester,
  ) async {
    // Coming up, Recently added and all four readouts on the rail are derived
    // from `moviesProvider`, which is not autoDispose and so is fetched once
    // for the life of the app. Invalidating only the derived providers re-ran
    // the window functions against that same cached list with a new
    // `DateTime.now()`: a pull that recomputed and fetched nothing, so a film
    // that landed, one that was added or a release date that moved never
    // appeared.
    final service = _scripted(movies: [_movie(id: 1)]) as _ScriptedRadarr;
    await _pump(tester, service: service);
    final before = service.libraryCalls;

    // Driven through the indicator's own state rather than a fling: the page is
    // one tall scroll view with a horizontal rail inside it, and what is under
    // test is the invalidate list the callback runs, not the gesture.
    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(service.libraryCalls, greaterThan(before));
  });

  testWidgets('pulling to refresh refetches the queue behind Queued too', (
    tester,
  ) async {
    // `radarrQueueSnapshotProvider` is not autoDispose either, and the rail's
    // fourth figure is read off it. Both readers of the queue have to refetch,
    // or `Queued` sits frozen beside three figures that moved.
    final service = _scripted() as _ScriptedRadarr;
    await _pump(tester, service: service);
    final before = service.queueCalls;

    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(service.queueCalls, before * 2);
  });

  testWidgets('a failed refresh keeps the count over the rows it still draws', (
    tester,
  ) async {
    // Same trap the NZBGet Overview names: `asData` is null on an `AsyncError`
    // that carries a retained value, while `AsyncValueWidget` under the header
    // draws that retained value at full ink beneath the unreachable band. The
    // header printed "—" over rows it was still showing.
    final service = _FlakyQueueRadarr(
      queue: [
        {
          'movie': {'title': 'Nickel Boys'},
          'trackedDownloadState': 'importFailed',
          'errorMessage': 'Radarr could not match the file',
        },
      ],
    );
    await _pump(tester, service: service);
    expect(_sectionHeader(tester, 'Needs attention').subtitle, '1');

    service.failFromNowOn = true;
    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    // The row is still on screen…
    expect(find.text('Import failed\u00A0· Nickel Boys'), findsOneWidget);
    // …so the figure above it still has to count it.
    expect(_sectionHeader(tester, 'Needs attention').subtitle, '1');
  });

  testWidgets('faults found in a queue walk that stopped short are a floor', (
    tester,
  ) async {
    // A full page and no `totalRecords`: the fault is in the rows that
    // arrived, and the rows behind them were never asked for.
    await _pump(
      tester,
      service: _CutShortQueueRadarr(
        queue: [
          {
            'movie': {'title': 'Nickel Boys'},
            'trackedDownloadState': 'importFailed',
            'errorMessage': 'Radarr could not match the file',
          },
        ],
      ),
    );

    expect(_sectionHeader(tester, 'Needs attention').subtitle, '1+');
  });

  testWidgets('a Radarr that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(), configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    // `.forService`, so the button deep-links to Radarr's own connection form
    // rather than to the settings index.
    expect(placeholder.service, ServiceKey.radarr);
    expect(find.byType(SectionHeader), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

SectionHeader _sectionHeader(WidgetTester tester, String title) => tester
    .widgetList<SectionHeader>(find.byType(SectionHeader))
    .firstWhere((header) => header.title == title);

Future<void> _pump(
  WidgetTester tester, {
  required RadarrService service,
  String? version = '5.4.6',
  bool configured = true,
  double textScaleFactor = 1.0,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on an exponential backoff, so one
      // `pumpAndSettle` would otherwise watch a deliberately failing section
      // retry a dozen times and never settle.
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => configured
              ? settingsWith(
                  radarrUrl: 'http://radarr.local:7878',
                  radarrApiKey: 'key',
                )
              : const SettingsModel(),
        ),
        radarrServiceProvider.overrideWith((ref) => service),
        serviceStatusClientFactoryProvider.overrideWith(
          (ref) =>
              ({
                required String baseUrl,
                required String apiKey,
                String? pinnedCertFingerprint,
                Map<String, String> accessHeaders = const {},
              }) => _StatusClient(version),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        ),
        home: const RadarrOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

RadarrService _scripted({
  List<RadarrMovie> movies = const [],
  List<dynamic> queue = const [],
  List<dynamic> history = const [],
  int? cutoffTotal,
}) => _ScriptedRadarr(
  movies: movies,
  queue: queue,
  history: history,
  cutoffTotal: cutoffTotal,
);

class _ScriptedRadarr extends FakeRadarrService {
  _ScriptedRadarr({
    this.movies = const [],
    this.queue = const [],
    this.history = const [],
    this.cutoffTotal,
  });

  final List<RadarrMovie> movies;
  final List<dynamic> queue;
  final List<dynamic> history;

  /// What `wanted/cutoff` reports as its `totalRecords`. Null is a fork that
  /// does not serve the endpoint, and draws no backlog row at all.
  final int? cutoffTotal;

  /// How many times the library was actually fetched.
  ///
  /// `moviesProvider` is not autoDispose, so this is the only way to tell a
  /// pull that refetched from a pull that re-read a session-old cache.
  int libraryCalls = 0;

  @override
  Future<List<RadarrMovie>> getMovies() async {
    libraryCalls++;
    return movies;
  }

  /// How many times the queue was actually fetched.
  ///
  /// Two independent readers ask for it: the Needs attention section and the
  /// snapshot behind the rail's `Queued` figure, and only one of them was
  /// autoDispose, so this separates a pull that refetched the queue from one
  /// that re-read a session-old snapshot.
  int queueCalls = 0;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async {
    queueCalls++;
    return queue;
  }

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => history;

  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => ArrRecordPage(records: const [], total: cutoffTotal);
}

/// A Radarr whose queue answers once and then stops.
///
/// The wire shape of a server that was reachable when the page loaded and is
/// not when the user pulls: the only way to get an `AsyncError` that carries a
/// retained value.
class _FlakyQueueRadarr extends _ScriptedRadarr {
  _FlakyQueueRadarr({super.queue});

  bool failFromNowOn = false;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async {
    if (failFromNowOn) throw Exception('queue failed');
    return super.getQueue(queryParameters: queryParameters);
  }
}

/// A Radarr whose queue walk stopped on a full page with no total.
class _CutShortQueueRadarr extends _ScriptedRadarr {
  _CutShortQueueRadarr({super.queue});

  @override
  Future<ArrRecordPage> getQueuePage({
    Map<String, dynamic>? queryParameters,
  }) async => ArrRecordPage(
    records: await getQueue(queryParameters: queryParameters),
    total: null,
    cutShort: true,
  );
}

class _FailingHistoryRadarr extends _ScriptedRadarr {
  _FailingHistoryRadarr(List<RadarrMovie> movies) : super(movies: movies);

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('history failed');
}

/// The reachability probe, answered offline.
///
/// A null [version] is the wire shape of a service that did not answer: the
/// probe throws, which is what `_loadServiceSummary` reads as offline.
class _StatusClient extends ApiClient {
  _StatusClient(this.version)
    : super(baseUrl: 'http://radarr.local:7878', apiKey: 'key');

  final String? version;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    if (version == null) throw const SocketException('Connection refused');
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'version': version},
    );
  }

  @override
  void close({bool force = false}) {}
}

RadarrMovie _movie({
  required int id,
  String title = 'Film',
  String? added,
  String? digitalRelease,
}) => RadarrMovie(
  id: id,
  title: title,
  sortTitle: title.toLowerCase(),
  sizeOnDisk: 0,
  status: 'released',
  hasFile: true,
  monitored: true,
  year: 2024,
  images: const [],
  tmdbId: id,
  runtime: 100,
  genres: const [],
  added: added,
  digitalRelease: digitalRelease,
);
