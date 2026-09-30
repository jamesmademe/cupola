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
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/sonarr_overview_screen.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  testWidgets('draws the regions in the order the mobile board draws them', (
    tester,
  ) async {
    await _pump(tester, service: _scripted());

    // Identity and the readouts come before any section, and only this tab
    // carries them.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Airing this week', 'Needs attention', 'Recently downloaded', 'History'],
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
      'opens the Sonarr Calendar tab',
      // Needs attention has no single destination: its rows belong to
      // different tabs, so it offers no link at all rather than a wrong one.
      null,
      'opens the Sonarr Library tab',
      'opens the Sonarr History tab',
    ]);
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(), version: '4.0.10');

    expect(
      find.semantics.byLabel('Sonarr, sonarr.local:8989, v4.0.10, Answering'),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets(
    'an unreachable Sonarr reads Did not answer, and its version is —',
    (tester) async {
      await _pump(tester, service: _scripted(), version: null);

      expect(
        find.semantics.byLabel('Sonarr, sonarr.local:8989, —, Did not answer'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the week counts series, and says how many', (tester) async {
    await _pump(
      tester,
      service: _scripted(
        series: [
          _series(
            id: 1,
            title: 'Severance',
            nextAiring: DateTime(
              today.year,
              today.month,
              today.day,
              21,
            ).toIso8601String(),
          ),
        ],
      ),
    );

    expect(_subtitleOf(tester, 'Airing this week'), 'next 7 days · 1 series');
    expect(find.text('Today'), findsOneWidget);
    // The row speaks as ONE sentence and silences its parts: day, series, then
    // the qualifier with the layout's dot turned into a comma.
    expect(
      find.semantics.byLabel('Today, Severance, 21:00, monitored'),
      findsOneWidget,
    );
  });

  testWidgets('a Sonarr that never said when anything airs reads —, not 0', (
    tester,
  ) async {
    // Two continuing series and no `nextAiring` anywhere: the server answered
    // the library and said nothing about airings. "0 series" here would be a
    // confident answer to a question nobody got a reply to.
    await _pump(
      tester,
      service: _scripted(
        series: [
          _series(id: 1, title: 'Severance'),
          _series(id: 2, title: 'Andor'),
        ],
      ),
    );

    expect(_subtitleOf(tester, 'Airing this week'), 'next 7 days · —');
    expect(find.text('Sonarr did not say when anything next airs'), findsOne);
    expect(find.text('Nothing airing this week'), findsNothing);
  });

  testWidgets('an empty week from a finished library is an honest empty', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        series: [_series(id: 1, title: 'The Wire', status: 'ended')],
      ),
    );

    expect(_subtitleOf(tester, 'Airing this week'), 'next 7 days · 0 series');
    expect(find.text('Nothing airing this week'), findsOne);
  });

  testWidgets('a library nobody could fetch reads —, never 0 series', (
    tester,
  ) async {
    // The regression this section was written against and still had: the
    // library fetch degraded to `[]`, the provider resolved *successfully*, and
    // the header printed "0 series" over "Nothing airing this week" — under an
    // identity band that its own probe had already marked Unreachable. The
    // confident claim was the fabricated one.
    await _pump(tester, service: _scripted(libraryThrows: true), version: null);

    expect(_subtitleOf(tester, 'Airing this week'), 'next 7 days · —');
    expect(find.text('Nothing airing this week'), findsNothing);
    expect(find.text('0 series'), findsNothing);
    // And the failure is a failure: the Retry this section documents is
    // reachable, which it was not while the fetch swallowed its own error.
    expect(
      find.descendant(
        of: find.byType(AppErrorState),
        matching: find.text('Retry'),
      ),
      findsWidgets,
    );
  });

  testWidgets('a fault row and a backlog row are spoken as sentences', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        queue: [
          {
            'series': {'title': 'Slow Horses'},
            'seasonNumber': 4,
            'trackedDownloadState': 'importFailed',
            'errorMessage': 'name does not match',
          },
        ],
        missing: const ArrRecordPage(records: [], total: 12),
        cutoff: const ArrRecordPage(records: [], total: 9),
      ),
    );

    expect(
      find.semantics.byLabel(
        'Import failed, Slow Horses S04, name does not match',
      ),
      findsOneWidget,
    );
    expect(
      find.semantics.byLabel(
        '12 missing monitored episodes, Sonarr keeps searching for them',
      ),
      findsOneWidget,
    );
    expect(
      find.semantics.byLabel(
        '9 episodes below your quality cutoff, '
        'Sonarr keeps searching for an upgrade',
      ),
      findsOneWidget,
    );
    // Three rows drawn, three counted.
    expect(_subtitleOf(tester, 'Needs attention'), '3');
  });

  testWidgets('a backlog nobody answered is absent, not zero', (tester) async {
    // The fake's default page carries `total: null` — the wire shape of a fork
    // that does not serve `wanted/*`. No row, and no reassuring "0 missing".
    await _pump(tester, service: _scripted());

    expect(find.textContaining('missing monitored'), findsNothing);
    expect(find.textContaining('below your quality cutoff'), findsNothing);
    expect(find.text('Nothing needs you'), findsOne);
  });

  testWidgets('a poster on the recently downloaded rail names its series', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        history: [
          {
            'eventType': 'downloadFolderImported',
            'seriesId': 7,
            'series': {'title': 'Severance', 'id': 7, 'images': const []},
            'episode': {'seasonNumber': 2, 'episodeNumber': 4},
            'date': now.toIso8601String(),
          },
        ],
      ),
    );

    expect(
      tester.getSemantics(
        find.ancestor(
          of: find.text('Severance'),
          matching: find.byType(PressableScale),
        ),
      ),
      containsSemantics(label: 'Severance', isButton: true),
    );
  });

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _FailingHistorySonarr(
        series: [
          _series(
            id: 1,
            title: 'Severance',
            nextAiring: DateTime(
              today.year,
              today.month,
              today.day + 1,
              21,
            ).toIso8601String(),
          ),
        ],
      ),
    );

    // The two failed regions say so in their own slots…
    expect(find.byType(AppErrorState), findsNWidgets(2));
    // …and the other two still drew.
    expect(find.byType(SectionHeader), findsNWidgets(4));
    expect(find.text('Severance'), findsOneWidget);
  });

  testWidgets('pulling to refresh refetches the library, not just the clock', (
    tester,
  ) async {
    // The week is derived from a session-cached library. Invalidating only the
    // derived provider re-ran the window function against the same cached list
    // with a new `DateTime.now()` — a pull that recomputed and fetched nothing,
    // so an episode that aired, a series added or a show that ended never
    // appeared.
    final service = _ScriptedSonarr(
      series: [_series(id: 1, title: 'Severance')],
    );
    await _pump(tester, service: service);
    // Two, not one: the KPI rail above reads its own non-swallowing copy of the
    // library (`sonarrKpiLibraryProvider`) rather than the browse grid's
    // swallowing one, so that a dark Sonarr prints "—" on the rail instead of
    // "Series 0". Two readers of `getSeriesOrThrow`, and the pull has to move
    // both of them.
    expect(service.libraryCalls, 2);

    // Driven through the indicator's own state rather than a fling: the page is
    // one tall scroll view with a horizontal rail inside it, and what is under
    // test is the invalidate list the callback runs, not the gesture.
    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(service.libraryCalls, 4);
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      service: _scripted(
        series: [
          _series(
            id: 1,
            title: 'A Very Long Series Title That Will Not Fit One Line',
            nextAiring: DateTime(
              today.year,
              today.month,
              today.day + 2,
              21,
            ).toIso8601String(),
          ),
        ],
        missing: const ArrRecordPage(records: [], total: 12),
        history: [
          {
            'eventType': 'downloadFolderImported',
            'seriesId': 7,
            'series': {
              'title': 'A Very Long Series Title That Will Not Fit One Line',
              'id': 7,
              'images': const [],
            },
            'episode': {'seasonNumber': 2, 'episodeNumber': 4},
            'date': now.toIso8601String(),
          },
        ],
      ),
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Sonarr that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(), configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    // `.forService`, so the button deep-links to Sonarr's own connection form
    // rather than to the settings index.
    expect(placeholder.service, ServiceKey.sonarr);
    // Not one section reached a provider, which is the point of checking
    // `isServiceConfigured` before them rather than letting four
    // `AsyncValueWidget`s each catch the same "not configured" throw: those
    // give the same pixels, but a `FutureProvider` that threw is a *failed*
    // provider on a backoff for a condition no waiting changes. The
    // `pumpAndSettle` above is what would catch it — a retrying provider never
    // settles.
    expect(find.byType(SectionHeader), findsNothing);
    expect(find.byType(ServiceKpiPeek), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

/// The subtitle the named section's header is printing.
String? _subtitleOf(WidgetTester tester, String title) => tester
    .widgetList<SectionHeader>(find.byType(SectionHeader))
    .firstWhere((header) => header.title == title)
    .subtitle;

Future<void> _pump(
  WidgetTester tester, {
  required SonarrService service,
  String? version = '4.0.10',
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
                  sonarrUrl: 'http://sonarr.local:8989',
                  sonarrApiKey: 'key',
                )
              : const SettingsModel(),
        ),
        sonarrServiceProvider.overrideWith((ref) => service),
        serviceStatusClientFactoryProvider.overrideWith(
          (ref) =>
              ({
                required String baseUrl,
                required String apiKey,
                String? pinnedCertFingerprint,
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
        home: const SonarrOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SonarrService _scripted({
  List<SonarrSeries> series = const [],
  List<dynamic> queue = const [],
  List<dynamic> history = const [],
  ArrRecordPage missing = const ArrRecordPage(records: [], total: null),
  ArrRecordPage cutoff = const ArrRecordPage(records: [], total: null),
  bool libraryThrows = false,
}) => _ScriptedSonarr(
  series: series,
  queue: queue,
  history: history,
  missing: missing,
  cutoff: cutoff,
  libraryThrows: libraryThrows,
);

class _ScriptedSonarr extends FakeSonarrService {
  _ScriptedSonarr({
    this.series = const [],
    this.queue = const [],
    this.history = const [],
    this.missing = const ArrRecordPage(records: [], total: null),
    this.cutoff = const ArrRecordPage(records: [], total: null),
    this.libraryThrows = false,
  });

  final List<SonarrSeries> series;
  final List<dynamic> queue;
  final List<dynamic> history;
  final ArrRecordPage missing;
  final ArrRecordPage cutoff;

  /// The library fetch fails, as it does for an unreachable or mis-keyed
  /// server.
  final bool libraryThrows;

  /// How many times the library was actually fetched.
  int libraryCalls = 0;

  @override
  Future<List<SonarrSeries>> getSeries() async => series;

  /// The read the Overview actually makes — the one that is allowed to fail.
  @override
  Future<List<SonarrSeries>> getSeriesOrThrow() async {
    libraryCalls++;
    if (libraryThrows) throw Exception('library unreachable');
    return series;
  }

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => queue;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => history;

  @override
  Future<ArrRecordPage> getMissingPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => missing;

  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => cutoff;
}

/// History fails; the library still answers.
///
/// Two regions read that page — Recently downloaded and History today — so this
/// fails exactly two of the four sections and proves the other two are
/// independent of them.
class _FailingHistorySonarr extends _ScriptedSonarr {
  _FailingHistorySonarr({super.series});

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
    : super(baseUrl: 'http://sonarr.local:8989', apiKey: 'key');

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

/// A series carrying only the fields the Overview reads.
SonarrSeries _series({
  required int id,
  String title = 'Series',
  String status = 'continuing',
  bool monitored = true,
  String? nextAiring,
}) => SonarrSeries(
  id: id,
  title: title,
  sortTitle: title.toLowerCase(),
  status: status,
  monitored: monitored,
  year: 2024,
  images: const [],
  tvdbId: id,
  runtime: 45,
  genres: const [],
  seasons: const [],
  nextAiring: nextAiring,
);
