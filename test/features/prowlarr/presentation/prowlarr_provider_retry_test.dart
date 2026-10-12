import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_indexer_detail_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_overview_provider.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/settings_scope.dart';

typedef _Read = (String, ProviderListenable<AsyncValue<Object?>>);

/// Every read provider a Prowlarr screen watches: the sources and every
/// provider derived from one.
final List<_Read> _reads = [
  ('indexers', prowlarrIndexersProvider),
  ('indexer stats', prowlarrIndexerStatsProvider),
  ('indexer status', prowlarrIndexerStatusProvider),
  ('health', prowlarrHealthProvider),
  ('recent history', prowlarrRecentHistoryProvider),
  (
    'history page',
    prowlarrHistoryPageProvider((page: 1, pageSize: 20, eventType: null)),
  ),
  (
    'stats window',
    prowlarrIndexerStatsForWindowProvider(ProwlarrStatsWindow.week),
  ),
  ('indexer by id', prowlarrIndexerByIdProvider(1)),
  ('indexer stat by id', prowlarrIndexerStatByIdProvider(1)),
  ('indexer status by id', prowlarrIndexerStatusByIdProvider(1)),
  ('indexer history', prowlarrIndexerHistoryProvider(1)),
  for (final kind in ProwlarrProviderKind.values) ...[
    ('${kind.name} list', prowlarrProvidersProvider(kind)),
    ('${kind.name} schema', prowlarrProviderSchemaProvider(kind)),
  ],
  ('download clients', prowlarrDownloadClientsProvider),
  ('categories', prowlarrCategoriesProvider),
  ('tag details', prowlarrTagDetailsProvider),
  ('tags', prowlarrTagsProvider),
  ('app profiles', prowlarrAppProfilesProvider),
  ('indexer schema', prowlarrIndexerSchemaProvider),
  ('overview attention', prowlarrOverviewAttentionProvider),
  ('overview indexers', prowlarrOverviewIndexersProvider),
  ('overview recent', prowlarrOverviewRecentProvider),
];

/// A source under Riverpod's default policy: the harness's own control.
final _defaultRetryIndexers = FutureProvider<List<ProwlarrIndexer>>(
  (ref) => ref.watch(prowlarrServiceProvider).getIndexers(),
);

/// Shorter than Riverpod's first retry delay (200 ms): a provider that is
/// going to retry is still reporting *loading* at this point.
const _settle = Duration(milliseconds: 50);

/// A Prowlarr that went dark: every GET fails the way a refused connection
/// does. `getCallCount` counts attempts, and a retry is an attempt.
FakeApiClient _darkProwlarr() => FakeApiClient()
  ..getException = DioException(
    requestOptions: RequestOptions(path: '/api/v1'),
    type: DioExceptionType.connectionError,
    message: 'Connection refused',
  );

ProviderContainer _containerOver(FakeApiClient api) {
  // No `retry:` on the container, deliberately: the policy under test is the
  // one each provider declares, and a container-wide override would hide it.
  final container = ProviderContainer(
    overrides: [
      prowlarrServiceProvider.overrideWithValue(ProwlarrService(api)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  testWidgets('control: under the default policy a dark Prowlarr spins', (
    tester,
  ) async {
    // Proves the harness can see a retry at all, so the test below is not
    // passing because nothing would ever have retried.
    final api = _darkProwlarr();
    final container = _containerOver(api);
    container.listen(_defaultRetryIndexers, (_, _) {});

    await tester.pump(_settle);
    expect(container.read(_defaultRetryIndexers).isLoading, isTrue);

    await tester.pump(const Duration(minutes: 1));
    expect(api.getCallCount, greaterThan(1));
  });

  testWidgets('every read settles on its first failure and is not retried', (
    tester,
  ) async {
    final api = _darkProwlarr();
    final container = _containerOver(api);
    for (final (_, provider) in _reads) {
      container.listen(provider, (_, _) {});
    }

    await tester.pump(_settle);
    for (final (name, provider) in _reads) {
      final state = container.read(provider);
      expect(state.isLoading, isFalse, reason: '$name is still loading');
      expect(state.hasError, isTrue, reason: '$name did not reach its error');
    }

    final attempts = api.getCallCount;
    await tester.pump(const Duration(minutes: 1));
    expect(api.getCallCount, attempts, reason: 'something retried on its own');
    for (final (name, provider) in _reads) {
      expect(container.read(provider).hasError, isTrue, reason: name);
    }
  });

  testWidgets('Retry on a derived read reaches its source', (tester) async {
    // The indexer detail page reads `prowlarrIndexerByIdProvider`, a lookup
    // over the list. Its Retry used to invalidate only the lookup, which
    // re-read the list's cached failure: with no automatic retry behind it,
    // that button would never have asked Prowlarr again.
    final api = _darkProwlarr();
    final container = _containerOver(api);
    container.listen(prowlarrIndexerByIdProvider(1), (_, _) {});
    await tester.pump(_settle);
    final attempts = api.getCallCount;

    container.invalidate(prowlarrIndexerByIdProvider(1));
    await tester.pump(_settle);
    expect(api.getCallCount, attempts, reason: 'the lookup alone re-asks');

    // What the page's Retry now does.
    container.invalidate(prowlarrIndexersProvider);
    await tester.pump(_settle);
    expect(api.getCallCount, attempts + 1);

    // And the answer, once Prowlarr is back, reaches the page.
    api
      ..getException = null
      ..getResponseData = [
        {'id': 1, 'name': 'NZBgeek', 'protocol': 'usenet', 'enable': true},
      ];
    container.invalidate(prowlarrIndexersProvider);
    await tester.pump(_settle);
    final indexer = container.read(prowlarrIndexerByIdProvider(1));
    expect(indexer.isLoading, isFalse);
    expect(indexer.value?.name, 'NZBgeek');
  });

  testWidgets('the indexer page\'s Retry asks Prowlarr again', (tester) async {
    final api = _darkProwlarr();
    final settings = await tester.runAsync(
      () => settingsScopeOverrides(configured: [ServiceKey.prowlarr]),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...?settings,
          prowlarrServiceProvider.overrideWithValue(ProwlarrService(api)),
        ],
        child: const MaterialApp(
          home: ProwlarrIndexerDetailScreen(indexerId: 1),
        ),
      ),
    );
    await tester.pump(_settle);
    expect(find.text('Prowlarr did not answer'), findsOneWidget);
    final attempts = api.getCallCount;

    await tester.tap(find.text('Retry'));
    await tester.pump(_settle);

    expect(api.getCallCount, attempts + 1);
    expect(find.text('Prowlarr did not answer'), findsOneWidget);
  });

  testWidgets('the indexer page checks the configuration first', (
    tester,
  ) async {
    // A deep link with Prowlarr not set up: the invitation, and no provider
    // reached, so no failure, and nothing to retry.
    final api = _darkProwlarr();
    final settings = await tester.runAsync(() => settingsScopeOverrides());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...?settings,
          prowlarrServiceProvider.overrideWithValue(ProwlarrService(api)),
        ],
        child: const MaterialApp(
          home: ProwlarrIndexerDetailScreen(indexerId: 1),
        ),
      ),
    );
    await tester.pump(_settle);

    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    expect(find.text('Prowlarr did not answer'), findsNothing);
    expect(api.getCallCount, 0);
  });

  testWidgets('"not configured" fails once, not ten times', (tester) async {
    // `watchApiClient` throws this from the service provider's own build, and
    // the default policy would retry it with backoff for a condition no
    // waiting changes.
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        initialActiveInstancesProvider.overrideWithValue(const {}),
      ],
    );
    addTearDown(container.dispose);
    var failures = 0;
    container.listen(
      prowlarrServiceProvider,
      (_, _) {},
      onError: (_, _) => failures++,
      fireImmediately: true,
    );
    container.listen(prowlarrTagsProvider, (_, _) {});

    await tester.pump(const Duration(minutes: 1));

    expect(failures, 1);
    final tags = container.read(prowlarrTagsProvider);
    expect(tags.isLoading, isFalse);
    expect(tags.error.toString(), contains('not configured'));
  });
}
