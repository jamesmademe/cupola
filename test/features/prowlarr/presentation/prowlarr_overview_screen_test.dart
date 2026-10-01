import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_overview_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('draws the regions in the order the board draws them', (
    tester,
  ) async {
    await _pump(tester);

    // Identity and the readouts come before any section, and only this tab
    // carries them.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    // What needs a decision first, then the service's own work, then history.
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Needs attention', 'Indexers', 'Recent'],
    );
    // Apps is absent, not stubbed: the applications endpoint carries neither a
    // sync timestamp nor a per-app failure.
    expect(find.text('Apps'), findsNothing);
  });

  testWidgets('each section link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.semanticHint),
      [
        // Needs attention has no single destination: a failing indexer and a
        // health check do not live on the same tab.
        null,
        'opens the Prowlarr Indexers tab',
        'opens the Prowlarr History tab',
      ],
    );
  });

  testWidgets('the indexer table names the window its figures come from', (
    tester,
  ) async {
    await _pump(
      tester,
      indexers: const [ProwlarrIndexer(id: 1, name: 'NZBgeek', enable: true)],
    );

    // The rows carry a day's query counts, so the heading says which day.
    expect(find.text('1 · by queries, last 24 h'), findsOneWidget);
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester, version: '1.30.2');

    expect(
      find.semantics.byLabel(
        'Prowlarr, prowlarr.local:9696, v1.30.2, Answering',
      ),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets(
    'an unreachable Prowlarr reads Did not answer, and its version is —',
    (tester) async {
      await _pump(tester, version: null);

      expect(
        find.semantics.byLabel(
          'Prowlarr, prowlarr.local:9696, —, Did not answer',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('a failing indexer is spoken as a sentence', (tester) async {
    await _pump(
      tester,
      indexers: const [ProwlarrIndexer(id: 4, name: 'Nyaa', enable: true)],
      statuses: [
        ProwlarrIndexerStatus(
          indexerId: 4,
          disabledTill: DateTime.now()
              .add(const Duration(minutes: 40))
              .toIso8601String(),
        ),
      ],
    );

    expect(
      find.semantics.byLabel(
        RegExp(r'^Nyaa, failing, disabled until \d\d:\d\d$'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an indexer with no sample in the window announces —', (
    tester,
  ) async {
    await _pump(
      tester,
      indexers: const [
        ProwlarrIndexer(
          id: 1,
          name: 'Idle',
          enable: true,
          protocol: 'torrent',
          privacy: 'private',
        ),
      ],
    );

    // Never "0 ms" and never "0 queries" for a figure nobody measured.
    expect(
      find.semantics.byLabel('Idle, torrent, private, —, —'),
      findsOneWidget,
    );
  });

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(tester, failHistory: true);

    // The failed region says so in its own slot…
    expect(find.byType(AppErrorState), findsOneWidget);
    // …and the other two still drew their headings.
    expect(find.byType(SectionHeader), findsNWidgets(3));
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      indexers: const [
        ProwlarrIndexer(
          id: 1,
          name: 'An Indexer With A Very Long Name Indeed',
          enable: true,
          protocol: 'torrent',
          privacy: 'private',
        ),
      ],
      stats: const ProwlarrIndexerStats(
        indexers: [
          ProwlarrIndexerStat(
            indexerId: 1,
            numberOfQueries: 298,
            averageResponseTime: 380,
          ),
        ],
      ),
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Prowlarr that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    expect(placeholder.service, ServiceKey.prowlarr);
    expect(find.byType(SectionHeader), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  List<ProwlarrIndexer> indexers = const [],
  ProwlarrIndexerStats stats = const ProwlarrIndexerStats(),
  List<ProwlarrIndexerStatus> statuses = const [],
  List<ProwlarrHealthIssue> health = const [],
  ProwlarrHistoryPage history = const ProwlarrHistoryPage(),
  bool failHistory = false,
  String? version = '1.30.2',
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
                  prowlarrUrl: 'http://prowlarr.local:9696',
                  prowlarrApiKey: 'key',
                )
              : const SettingsModel(),
        ),
        prowlarrIndexersProvider.overrideWith((ref) async => indexers),
        prowlarrIndexerStatsProvider.overrideWith((ref) async => stats),
        prowlarrIndexerStatusProvider.overrideWith((ref) async => statuses),
        prowlarrHealthProvider.overrideWith((ref) async => health),
        prowlarrRecentHistoryProvider.overrideWith((ref) async {
          if (failHistory) throw Exception('history failed');
          return history;
        }),
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
        home: const ProwlarrOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The reachability probe, answered offline.
///
/// A null [version] is the wire shape of a service that did not answer: the
/// probe throws, which is what `_loadServiceSummary` reads as offline.
class _StatusClient extends ApiClient {
  _StatusClient(this.version)
    : super(baseUrl: 'http://prowlarr.local:9696', apiKey: 'key');

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
