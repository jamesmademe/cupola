import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/arr_tab_screen.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../../test_helpers/settings_scope.dart';

void main() {
  group('the Queue and History tabs', () {
    testWidgets('Queue lists what the arr is downloading', (tester) async {
      final service = _FakeRadarrActivityService(
        queueItems: const [
          {'title': 'Queued.Movie', 'status': 'queued'},
        ],
      );

      await _pumpWithRadarrService(
        tester,
        service: service,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.queue,
        ),
      );

      expect(find.text('Queued.Movie'), findsOneWidget);
      expect(service.queueCalls, 1);
      expect(service.historyCalls, 0);
    });

    testWidgets('History lists what it grabbed, and says so', (tester) async {
      final service = _FakeRadarrActivityService(
        historyItems: const [
          {'sourceTitle': 'Grabbed.Release', 'eventType': 'grabbed'},
        ],
      );

      await _pumpWithRadarrService(
        tester,
        service: service,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.history,
        ),
      );

      expect(find.text('Grabbed.Release'), findsOneWidget);
      expect(find.text('Grabbed'), findsOneWidget);
      expect(service.historyCalls, 1);
      expect(service.queueCalls, 0);
    });
  });

  group('a long History', () {
    testWidgets('draws its first page while the rest is read, then all of it', (
      tester,
    ) async {
      final rest = Completer<void>();
      final service = _FakeRadarrActivityService(
        historyItems: const [
          {'sourceTitle': 'Newest.Release', 'eventType': 'grabbed'},
          {'sourceTitle': 'Oldest.Release', 'eventType': 'grabbed'},
        ],
        historyFirstPage: const [
          {'sourceTitle': 'Newest.Release', 'eventType': 'grabbed'},
        ],
        historyHeld: rest,
      );

      await tester.pumpWidget(
        _host(
          service,
          const ArrTabScreen(
            serviceType: ServiceType.movies,
            mode: ArrTabMode.history,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The first page is a list on screen, with the loading rows under it.
      expect(find.text('Newest.Release'), findsOneWidget);
      expect(find.text('Oldest.Release'), findsNothing);
      expect(find.byType(ShimmerList), findsOneWidget);

      rest.complete();
      await tester.pumpAndSettle();

      expect(find.text('Newest.Release'), findsOneWidget);
      expect(find.text('Oldest.Release'), findsOneWidget);
      expect(find.byType(ShimmerList), findsNothing);
    });

    testWidgets('a page that fails keeps the rows and says the rest did not '
        'arrive', (tester) async {
      final rest = Completer<void>();
      final service = _FakeRadarrActivityService(
        historyFirstPage: const [
          {'sourceTitle': 'Newest.Release', 'eventType': 'grabbed'},
        ],
        historyHeld: rest,
        historyFailure: Exception('connection reset'),
      );

      await tester.pumpWidget(
        _host(
          service,
          const ArrTabScreen(
            serviceType: ServiceType.movies,
            mode: ArrTabMode.history,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Newest.Release'), findsOneWidget);
      expect(find.byType(ShimmerList), findsOneWidget);

      rest.complete();
      await tester.pumpAndSettle();

      // What was being read stays; the loading rows give way to the notice.
      expect(find.text('Newest.Release'), findsOneWidget);
      expect(find.byType(ShimmerList), findsNothing);
      expect(find.byType(InlineErrorRetry), findsOneWidget);
      expect(
        find.textContaining('the rest of the history did not arrive'),
        findsOneWidget,
      );

      // Its Retry reads the history again, from the first page.
      final calls = service.historyCalls;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(service.historyCalls, calls + 1);
    });

    testWidgets('with no first page yet it is the skeleton, as before', (
      tester,
    ) async {
      final service = _FakeRadarrActivityService(
        historyHeld: Completer<void>(),
      );

      await tester.pumpWidget(
        _host(
          service,
          const ArrTabScreen(
            serviceType: ServiceType.movies,
            mode: ArrTabMode.history,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ShimmerList), findsOneWidget);
    });
  });

  group('the Wanted tab', () {
    testWidgets('shows missing items and cutoff movie quality profile names', (
      tester,
    ) async {
      final service = _FakeRadarrActivityService(
        missingItems: const [
          {'title': 'Missing Movie'},
        ],
        cutoffItems: const [
          {
            'id': 42,
            'title': 'Cutoff Movie',
            'status': 'released',
            'qualityProfileId': 7,
            'sizeOnDisk': 8003897815,
          },
        ],
        qualityProfileResponses: const [
          [
            {'id': 7, 'name': 'HD-1080p'},
          ],
        ],
      );

      await _pumpWithRadarrService(
        tester,
        service: service,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.wanted,
        ),
      );

      expect(find.text('Missing Movie'), findsOneWidget);
      expect(service.missingCalls, 1);

      await tester.tap(find.text('Cutoff unmet'));
      await tester.pumpAndSettle();

      expect(find.text('Cutoff Movie'), findsOneWidget);
      expect(find.text('HD-1080p'), findsOneWidget);
      expect(service.cutoffCalls, 1);
      expect(service.qualityProfileCalls, 1);
    });

    testWidgets('switching segments clears cached movie quality profiles', (
      tester,
    ) async {
      final service = _FakeRadarrActivityService(
        missingItems: const [
          {'title': 'Missing Movie'},
        ],
        cutoffItems: const [
          {
            'id': 42,
            'title': 'Cutoff Movie',
            'status': 'released',
            'qualityProfileId': 7,
            'sizeOnDisk': 8003897815,
          },
        ],
        qualityProfileResponses: const [
          [
            {'id': 7, 'name': 'HD-1080p'},
          ],
          [
            {'id': 7, 'name': 'Ultra HD'},
          ],
        ],
      );

      await _pumpWithRadarrService(
        tester,
        service: service,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.wanted,
        ),
      );

      await tester.tap(find.text('Cutoff unmet'));
      await tester.pumpAndSettle();

      expect(find.text('HD-1080p'), findsOneWidget);
      expect(service.cutoffCalls, 1);
      expect(service.qualityProfileCalls, 1);

      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      expect(find.text('Missing Movie'), findsOneWidget);
      expect(service.missingCalls, 2);

      await tester.tap(find.text('Cutoff unmet'));
      await tester.pumpAndSettle();

      expect(find.text('Ultra HD'), findsOneWidget);
      expect(find.text('HD-1080p'), findsNothing);
      expect(service.cutoffCalls, 2);
      expect(service.qualityProfileCalls, 2);
    });

    testWidgets('switches wanted segments for series hierarchy', (
      tester,
    ) async {
      final service = _FakeSonarrActivityService(
        missingItems: const [
          {
            'id': 1,
            'title': 'Pilot',
            'series': {'title': 'Missing Show'},
            'seasonNumber': 1,
            'episodeNumber': 1,
          },
        ],
        cutoffItems: const [
          {
            'id': 2,
            'title': 'Finale',
            'series': {'title': 'Cutoff Show'},
            'seasonNumber': 1,
            'episodeNumber': 2,
            'episodeFile': {'size': 5307309140},
          },
        ],
      );

      await _pumpWithSonarrService(
        tester,
        service: service,
        child: const ArrTabScreen(
          serviceType: ServiceType.series,
          mode: ArrTabMode.wanted,
        ),
      );

      expect(find.text('Missing Show'), findsOneWidget);
      expect(service.missingCalls, 1);

      await tester.tap(find.text('Cutoff unmet'));
      await tester.pumpAndSettle();

      expect(find.text('Cutoff Show'), findsOneWidget);
      expect(service.cutoffCalls, 1);
    });
  });
}

Future<void> _pumpWithRadarrService(
  WidgetTester tester, {
  required _FakeRadarrActivityService service,
  required Widget child,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The tabs ask whether there is a Radarr before they read one.
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices([ServiceKey.radarr]),
        ),
        radarrServiceProvider.overrideWith((ref) => service),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpWithSonarrService(
  WidgetTester tester, {
  required _FakeSonarrActivityService service,
  required Widget child,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The tab asks whether there is a Sonarr before it reads one.
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices([ServiceKey.sonarr]),
        ),
        sonarrServiceProvider.overrideWith((ref) => service),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeRadarrActivityService extends RadarrService {
  _FakeRadarrActivityService({
    this.queueItems = const [],
    this.historyItems = const [],
    this.missingItems = const [],
    this.cutoffItems = const [],
    this.qualityProfileResponses = const [],
    this.historyFirstPage,
    this.historyHeld,
    this.historyFailure,
  }) : super(ApiClient(baseUrl: 'https://radarr.example.com', apiKey: 'key'));

  /// When set, History says this much, and then waits for [historyHeld].
  final List<dynamic>? historyFirstPage;
  final Completer<void>? historyHeld;

  /// When set, History fails with this once [historyHeld] is let go.
  final Object? historyFailure;

  final List<dynamic> queueItems;
  final List<dynamic> historyItems;
  final List<dynamic> missingItems;
  final List<dynamic> cutoffItems;
  final List<List<Map<String, dynamic>>> qualityProfileResponses;

  int queueCalls = 0;
  int historyCalls = 0;
  int missingCalls = 0;
  int cutoffCalls = 0;
  int qualityProfileCalls = 0;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async {
    queueCalls++;
    return queueItems;
  }

  @override
  Future<List<dynamic>> getAllHistory({
    Map<String, dynamic>? queryParameters,
    void Function(List<dynamic> records)? onProgress,
  }) async {
    historyCalls++;
    final first = historyFirstPage;
    if (first != null) onProgress?.call(first);
    await historyHeld?.future;
    final failure = historyFailure;
    // The first read only: a Retry gets an answer.
    if (failure != null && historyCalls == 1) throw failure;
    return historyItems;
  }

  @override
  Future<List<dynamic>> getAllMissing({
    Map<String, dynamic>? queryParameters,
  }) async {
    missingCalls++;
    return missingItems;
  }

  @override
  Future<List<dynamic>> getAllCutoff({
    Map<String, dynamic>? queryParameters,
  }) async {
    cutoffCalls++;
    return cutoffItems;
  }

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async {
    qualityProfileCalls++;

    if (qualityProfileResponses.isEmpty) {
      return const [];
    }

    final responseIndex = qualityProfileCalls <= qualityProfileResponses.length
        ? qualityProfileCalls - 1
        : qualityProfileResponses.length - 1;
    return qualityProfileResponses[responseIndex];
  }
}

class _FakeSonarrActivityService extends SonarrService {
  _FakeSonarrActivityService({
    this.missingItems = const [],
    this.cutoffItems = const [],
  }) : super(ApiClient(baseUrl: 'https://sonarr.example.com', apiKey: 'key'));

  final List<dynamic> missingItems;
  final List<dynamic> cutoffItems;

  int missingCalls = 0;
  int cutoffCalls = 0;

  @override
  Future<List<dynamic>> getAllMissing({
    Map<String, dynamic>? queryParameters,
  }) async {
    missingCalls++;
    return missingItems;
  }

  @override
  Future<List<dynamic>> getAllCutoff({
    Map<String, dynamic>? queryParameters,
  }) async {
    cutoffCalls++;
    return cutoffItems;
  }
}

/// The tab over a Radarr, without settling: a read held open keeps the
/// skeleton animating, and a settle would wait for it forever.
Widget _host(_FakeRadarrActivityService service, Widget child) => ProviderScope(
  overrides: [
    currentSettingsProvider.overrideWith(
      (ref) => settingsWithServices([ServiceKey.radarr]),
    ),
    radarrServiceProvider.overrideWith((ref) => service),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);
