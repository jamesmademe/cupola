import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
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

  testWidgets('an unreachable Radarr reads Unreachable, and its version is —', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(), version: null);

    expect(
      find.semantics.byLabel('Radarr, radarr.local:7878, —, Unreachable'),
      findsOneWidget,
    );
  });

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
    expect(find.byType(AppErrorState), findsOneWidget);
    // …and the other three still drew.
    expect(find.byType(SectionHeader), findsNWidgets(4));
    expect(find.text('Soon'), findsOneWidget);
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
        cutoff: const [
          {'id': 1},
          {'id': 2},
        ],
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
        '2 films below your quality cutoff, '
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
      containsSemantics(label: 'Dune: Part Two', isButton: true),
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
        cutoff: const [
          {'id': 1},
        ],
      ),
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
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
  List<dynamic> cutoff = const [],
}) => _ScriptedRadarr(
  movies: movies,
  queue: queue,
  history: history,
  cutoff: cutoff,
);

class _ScriptedRadarr extends FakeRadarrService {
  _ScriptedRadarr({
    this.movies = const [],
    this.queue = const [],
    this.history = const [],
    this.cutoff = const [],
  });

  final List<RadarrMovie> movies;
  final List<dynamic> queue;
  final List<dynamic> history;
  final List<dynamic> cutoff;

  @override
  Future<List<RadarrMovie>> getMovies() async => movies;

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
  Future<List<dynamic>> getAllCutoff() async => cutoff;
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
    if (version == null) throw Exception('unreachable');
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
