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
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_overview_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  testWidgets('draws the regions the client can fill, in the board order', (
    tester,
  ) async {
    await _pump(tester, service: _scripted());

    // Identity and the readouts come before any section, and only this tab
    // carries them.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    // Coming up and Recently added are absent on purpose: `/api/v1/calendar`
    // and `/api/v1/book` are calls this client does not make, and an empty
    // region would answer a question nobody asked the server.
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Needs attention', 'Root folder', 'History'],
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
        // Needs attention has no single destination: its rows belong to
        // different tabs, so it offers no link at all rather than a wrong one.
        null,
        // Root folder's board link is "Manage", which is a settings page and
        // not a tab.
        null,
        'opens the Readarr History tab',
      ],
    );
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(), version: '0.4.0');

    expect(
      find.semantics.byLabel('Readarr, readarr.local:8787, v0.4.0, Answering'),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets(
    'an unreachable Readarr reads Did not answer, and its version is —',
    (tester) async {
      await _pump(tester, service: _scripted(), version: null);

      expect(
        find.semantics.byLabel(
          'Readarr, readarr.local:8787, —, Did not answer',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(tester, service: _FailingHistoryReadarr());

    // The failed region says so in its own slot…
    expect(find.byType(InlineErrorRetry), findsOneWidget);
    expect(
      find.textContaining(", so today's history is not shown."),
      findsOneWidget,
    );
    // …and the other two still drew.
    expect(find.byType(SectionHeader), findsNWidgets(3));
    // Including the resting state, which is reachable now that no standing
    // advisory is pushed onto the head of the list on every load.
    expect(find.text('Nothing needs you'), findsOneWidget);
  });

  testWidgets('a count whose source did not answer reads "—", not 0', (
    tester,
  ) async {
    await _pump(tester, service: _FailingQueueReadarr());

    final header = tester
        .widgetList<SectionHeader>(find.byType(SectionHeader))
        .first;
    expect(header.title, 'Needs attention');
    // "0" here would be a claim that nothing needs the user, made about a
    // queue that was never read.
    expect(header.subtitle, '—');
    expect(header.subtitle, isNot('0'));
  });

  testWidgets('a root folder with no free-space figure reads "—", not 0 B', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        rootFolders: const [
          {'path': '/data/books'},
        ],
      ),
    );

    expect(find.text('/data/books'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('0 B free'), findsNothing);
    // Spoken, the em dash becomes a reason rather than a shrug.
    expect(
      find.semantics.byLabel('/data/books, free space unknown'),
      findsOneWidget,
    );
  });

  testWidgets('every attention row is spoken as one sentence', (tester) async {
    await _pump(
      tester,
      service: _scripted(
        authors: [_author(books: 10, files: 8)],
        queue: [
          {
            'book': {'title': 'Orbital'},
            'trackedDownloadState': 'importFailed',
            'errorMessage': 'epub could not be matched',
          },
        ],
      ),
    );

    expect(
      find.semantics.byLabel(
        'Import failed, Orbital, epub could not be matched',
      ),
      findsOneWidget,
    );
    expect(
      find.semantics.byLabel('2 books missing a file, across 1 author'),
      findsOneWidget,
    );
  });

  testWidgets('a history row is spoken as one sentence', (tester) async {
    await _pump(
      tester,
      service: _scripted(
        history: [
          {
            'book': {'title': 'James'},
            // The spelling Readarr actually sends. Every fixture on this
            // screen used to say `downloadFolderImported`, which is how
            // Radarr and Sonarr spell an import and a string Readarr never
            // writes, so the suite was green on a screen that had never seen
            // a Readarr record.
            'eventType': 'bookFileImported',
            'date': today
                .add(const Duration(hours: 9))
                .toUtc()
                .toIso8601String(),
            'quality': {
              'quality': {'name': 'epub'},
            },
          },
        ],
      ),
    );

    expect(find.text('James · imported'), findsOneWidget);
    expect(
      tester
          .widgetList<ServiceOverviewRow>(find.byType(ServiceOverviewRow))
          .where((row) => row.spoken.startsWith('James, Imported, epub')),
      hasLength(1),
    );
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      service: _scripted(
        authors: [_author(books: 40, files: 1)],
        rootFolders: const [
          {'path': '/mnt/tank/media/library/books', 'freeSpace': 902000000000},
        ],
        queue: [
          {
            'book': {'title': 'A Very Long Book Title That Will Not Fit'},
            'trackedDownloadState': 'importFailed',
            'errorMessage': 'the file could not be matched to any known book',
          },
        ],
      ),
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Readarr that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(), configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    // `.forService`, so the button deep-links to Readarr's own connection form
    // rather than to the settings index.
    expect(placeholder.service, ServiceKey.readarr);
    // And no provider was ever reached: a `FutureProvider` that throws
    // "Readarr not configured" is a failed provider, which schedules a retry
    // for a condition no waiting changes.
    expect(find.byType(SectionHeader), findsNothing);
  });

  testWidgets('a failed refresh keeps the folder count it was showing', (
    tester,
  ) async {
    // `AsyncValueWidget` draws a retained value at full ink under the
    // unreachable band, precisely so a screen keeps its last readout. Reading
    // the count off `asData` threw that away: `asData` is null on an
    // `AsyncError`, retained value or not, so the header went silent about
    // three folders the section below it was still drawing.
    final service = _FlakyRootFoldersReadarr(
      rootFolders: const [
        {'path': '/data/books', 'freeSpace': 1000},
        {'path': '/data/comics', 'freeSpace': 2000},
      ],
    );
    await _pump(tester, service: service);
    expect(_rootFolderHeader(tester).subtitle, '2 folders');

    service.failFromNowOn = true;
    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    // The rows are still there…
    expect(find.text('/data/books'), findsOneWidget);
    expect(find.text('/data/comics'), findsOneWidget);
    // …so the count above them has to still be true.
    expect(_rootFolderHeader(tester).subtitle, '2 folders');
  });
}

SectionHeader _rootFolderHeader(WidgetTester tester) => tester
    .widgetList<SectionHeader>(find.byType(SectionHeader))
    .firstWhere((header) => header.title == 'Root folder');

// ─── Harness ────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required ReadarrService service,
  String? version = '0.4.0',
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
                  readarrUrl: 'http://readarr.local:8787',
                  readarrApiKey: 'key',
                )
              : const SettingsModel(),
        ),
        readarrServiceProvider.overrideWith((ref) => service),
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
        home: const ReadarrOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ReadarrService _scripted({
  List<ReadarrAuthor> authors = const [],
  List<dynamic> queue = const [],
  List<dynamic> history = const [],
  List<Map<String, dynamic>> rootFolders = const [],
}) => _ScriptedReadarr(
  authors: authors,
  queue: queue,
  history: history,
  rootFolders: rootFolders,
);

ReadarrAuthor _author({int id = 1, int books = 0, int files = 0}) =>
    ReadarrAuthor(
      id: id,
      authorName: 'Author $id',
      monitored: true,
      bookCount: books,
      bookFileCount: files,
    );

class _ScriptedReadarr extends ReadarrService {
  _ScriptedReadarr({
    this.authors = const [],
    this.queue = const [],
    this.history = const [],
    this.rootFolders = const [],
  }) : super(FakeApiClient());

  final List<ReadarrAuthor> authors;
  final List<dynamic> queue;
  final List<dynamic> history;
  final List<Map<String, dynamic>> rootFolders;

  @override
  Future<List<ReadarrAuthor>> getAuthors() async => authors;

  // The author list reads this one: a failed fetch has to reach the page.
  @override
  Future<List<ReadarrAuthor>> getAuthorsOrThrow() async => authors;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => queue;

  /// The walk, as the shared fakes answer it: the scripted rows are the whole
  /// queue, so their count is its total.
  @override
  Future<ArrRecordPage> getQueuePage({
    Map<String, dynamic>? queryParameters,
  }) async {
    final records = await getQueue(queryParameters: queryParameters);
    return ArrRecordPage(records: records, total: records.length);
  }

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => history;

  @override
  Future<List<Map<String, dynamic>>> fetchRootFolders() async => rootFolders;
}

class _FailingHistoryReadarr extends _ScriptedReadarr {
  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('history failed');
}

/// A Readarr whose root folders answer once and then stop.
///
/// The wire shape of a server that was reachable when the page loaded and is
/// not when the user pulls, which is the only way to get an `AsyncError`
/// carrying a retained value.
class _FlakyRootFoldersReadarr extends _ScriptedReadarr {
  _FlakyRootFoldersReadarr({super.rootFolders});

  bool failFromNowOn = false;

  @override
  Future<List<Map<String, dynamic>>> fetchRootFolders() async {
    if (failFromNowOn) throw Exception('root folders failed');
    return rootFolders;
  }
}

class _FailingQueueReadarr extends _ScriptedReadarr {
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
    : super(baseUrl: 'http://readarr.local:8787', apiKey: 'key');

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
