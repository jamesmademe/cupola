import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/lidarr_overview_provider.dart';
import 'package:cupola/features/music/presentation/lidarr_overview_screen.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  testWidgets('draws the regions in the order the narrow board draws them', (
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
      // No "Coming up": the week the board opens on needs `/api/v1/calendar`,
      // which this client does not call, and an artist row carries no dates to
      // derive it from the way a Radarr film does.
      ['Needs attention', 'Recently added', 'History', 'Root folders'],
    );
  });

  testWidgets('each section link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester, service: _scripted());

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.semanticHint),
      [
        // Needs attention has no single destination: the faults belong to
        // Queue and the backlog to Wanted.
        null,
        'opens the Lidarr Library tab',
        'opens the Lidarr History tab',
        // Root folders is a settings surface, and the bar has no tab for it.
        null,
      ],
    );
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(), version: '2.9.6');

    expect(
      find.semantics.byLabel('Lidarr, lidarr.local:8686, v2.9.6, Answering'),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets('a section whose source failed reads — and not 0', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _FailingQueueLidarr(
        artists: [_artist(id: 1, name: 'Alvvays', added: today)],
      ),
    );

    // The failed region says so in its own slot…
    expect(find.byType(AppErrorState), findsOneWidget);

    final headers = tester
        .widgetList<SectionHeader>(find.byType(SectionHeader))
        .toList();
    // …its count is the unanswered figure and not a reassuring zero, which is
    // the whole of the em dash rule: "nobody answered" must not be spelled the
    // way "the server said none" is…
    expect(headers.first.title, 'Needs attention');
    expect(headers.first.subtitle, '—');
    expect(headers.first.subtitle, isNot('0'));
    // …and the other three still drew.
    expect(headers, hasLength(4));
    expect(find.text('Alvvays'), findsOneWidget);
  });

  testWidgets('a fault row and a backlog row are spoken as sentences', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        queue: [
          {
            'artist': {'artistName': 'Mk.gee'},
            'album': {'title': 'Two Star'},
            'trackedDownloadState': 'importFailed',
            'errorMessage': 'Lidarr could not match the tracks',
          },
        ],
        missing: const ArrRecordPage(
          records: [
            {
              'id': 1,
              'artist': {'artistName': 'The Cure'},
            },
            {
              'id': 2,
              'artist': {'artistName': 'Alvvays'},
            },
          ],
          total: 2,
        ),
      ),
    );

    // One node for the whole row: the parts are fragments of one fact, and the
    // em dash between artist and album is spoken as a pause rather than named.
    expect(
      find.semantics.byLabel(
        'Import failed, Mk.gee, Two Star, Lidarr could not match the tracks',
      ),
      findsOneWidget,
    );
    expect(
      find.semantics.byLabel(
        '2 missing monitored albums, across 2 artists, '
        'Lidarr keeps searching for them',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an album imported track by track speaks as one row', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        history: ArrRecordPage(
          records: [
            for (var i = 0; i < 3; i++)
              {
                'eventType': 'trackFileImported',
                'date': today
                    .add(Duration(hours: 1, minutes: i))
                    .toIso8601String(),
                'artist': {'artistName': 'Cindy Lee'},
                'album': {'id': 4, 'title': 'Diamond Jubilee'},
                'quality': {
                  'quality': {'name': 'FLAC'},
                },
              },
          ],
          total: 3,
        ),
      ),
    );

    expect(find.textContaining('Cindy Lee — Diamond Jubilee'), findsOneWidget);
    expect(find.textContaining('3 tracks'), findsOneWidget);
  });

  testWidgets('a poster on the recently added rail has an accessible name', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        artists: [
          _artist(id: 7, name: 'Godspeed You! Black Emperor', added: today),
        ],
      ),
    );

    expect(
      tester.getSemantics(
        find.ancestor(
          of: find.text('Godspeed You! Black Emperor'),
          matching: find.byType(PressableScale),
        ),
      ),
      containsSemantics(label: 'Godspeed You! Black Emperor', isButton: true),
    );
  });

  testWidgets('an artist whose statistics never arrived is not "0 albums"', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        artists: [
          _artist(id: 7, name: 'Cindy Lee', added: today, statistics: null),
          _artist(id: 8, name: 'Alvvays', added: today, albumCount: 4),
        ],
      ),
    );

    // `albumCount` reads a nullable `statistics` and falls back to zero, so the
    // tile that captioned it unguarded said "0 albums" — and said it to a
    // screen reader too — about an artist the server described no count for.
    expect(find.text('0 albums'), findsNothing);
    expect(find.text('4 albums'), findsOneWidget);

    expect(
      tester.getSemantics(
        find.ancestor(
          of: find.text('Cindy Lee'),
          matching: find.byType(PressableScale),
        ),
      ),
      containsSemantics(label: 'Cindy Lee', value: ''),
    );
  });

  testWidgets('the recently added rail states no figure it cannot hold', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        artists: [
          for (var i = 0; i < lidarrRecentlyAddedLimit + 4; i++)
            _artist(id: i, name: 'Artist $i', added: today),
        ],
      ),
    );

    final recentlyAdded = tester
        .widgetList<SectionHeader>(find.byType(SectionHeader))
        .firstWhere((header) => header.title == 'Recently added');
    // Ten artists were added and the rail holds six: a count here would be the
    // cap wearing the clothes of a census. The word stays — the rail is one
    // granularity coarser than the board drew — and the figure goes.
    expect(recentlyAdded.subtitle, 'artists');
    expect(recentlyAdded.subtitle, isNot(contains('6')));
  });

  testWidgets('a root folder speaks its path and its free space together', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        rootFolders: const [
          {'path': '/data/music', 'freeSpace': 1979120929996},
        ],
      ),
    );

    expect(find.semantics.byLabel('/data/music, 1.8 TB free'), findsOneWidget);
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      service: _scripted(
        artists: [
          _artist(
            id: 1,
            name: 'A Very Long Artist Name That Will Not Fit One Line',
            added: today,
          ),
        ],
        rootFolders: const [
          {'path': '/mnt/tank/media/music/library', 'freeSpace': 1979120929996},
        ],
        missing: const ArrRecordPage(
          records: [
            {'id': 1},
          ],
          total: 1,
        ),
      ),
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Lidarr that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(), configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    // `.forService`, so the button deep-links to Lidarr's own connection form
    // rather than to the settings index.
    expect(placeholder.service, ServiceKey.lidarr);
    // Nothing behind it: the providers are never reached, so nothing schedules
    // a retry for a condition no waiting changes.
    expect(find.byType(SectionHeader), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required LidarrService service,
  String? version = '2.9.6',
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
                  lidarrUrl: 'http://lidarr.local:8686',
                  lidarrApiKey: 'key',
                )
              : const SettingsModel(),
        ),
        lidarrServiceProvider.overrideWith((ref) => service),
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
        home: const LidarrOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

LidarrService _scripted({
  List<LidarrArtist> artists = const [],
  List<dynamic> queue = const [],
  ArrRecordPage history = const ArrRecordPage(records: [], total: 0),
  ArrRecordPage missing = const ArrRecordPage(records: [], total: 0),
  List<Map<String, dynamic>> rootFolders = const [],
}) => _ScriptedLidarr(
  artists: artists,
  queue: queue,
  history: history,
  missing: missing,
  rootFolders: rootFolders,
);

/// A [FakeLidarrService] whose four Overview sources are scripted.
///
/// `getRootFolders` is overridden like the rest and not left to the shared
/// fake: the production method lets its failure travel, so an unscripted one
/// would reach a real `Dio` and leave a live request behind the test.
class _ScriptedLidarr extends FakeLidarrService {
  _ScriptedLidarr({
    this.artists = const [],
    this.queue = const [],
    this.history = const ArrRecordPage(records: [], total: 0),
    this.missing = const ArrRecordPage(records: [], total: 0),
    this.rootFolders = const [],
  });

  final List<LidarrArtist> artists;
  final List<dynamic> queue;
  final ArrRecordPage history;
  final ArrRecordPage missing;
  final List<Map<String, dynamic>> rootFolders;

  @override
  Future<List<LidarrArtist>> getArtists() async => artists;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => queue;

  @override
  Future<ArrRecordPage> getHistoryPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => history;

  @override
  Future<ArrRecordPage> getMissingPage({
    int page = 1,
    int pageSize = 20,
  }) async => missing;

  @override
  Future<List<Map<String, dynamic>>> getRootFolders() async => rootFolders;
}

class _FailingQueueLidarr extends _ScriptedLidarr {
  _FailingQueueLidarr({super.artists});

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('queue failed');
}

/// The reachability probe, answered offline.
///
/// A null [version] is the wire shape of a service that did not answer: the
/// probe throws, which is what `_loadServiceSummary` reads as offline.
class _StatusClient extends ApiClient {
  _StatusClient(this.version)
    : super(baseUrl: 'http://lidarr.local:8686', apiKey: 'key');

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

/// One artist. Pass `statistics: null` for the record a server sent without
/// them — the shape every "0 albums" caption was really describing.
LidarrArtist _artist({
  required int id,
  String name = 'Artist',
  DateTime? added,
  int albumCount = 3,
  Object? statistics = _unset,
}) => LidarrArtist(
  id: id,
  artistName: name,
  status: 'continuing',
  monitored: true,
  images: const [],
  genres: const [],
  added: added?.toIso8601String(),
  statistics: identical(statistics, _unset)
      ? {'albumCount': albumCount}
      : statistics as Map<String, dynamic>?,
);

/// Distinguishes "the caller said nothing" from "the caller said null".
const Object _unset = Object();
