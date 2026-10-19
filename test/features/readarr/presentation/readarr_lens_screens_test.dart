/// Readarr's Activity and History tabs follow the connection the lens is on.
///
/// Both hold their request in state, so moving the lens while they are mounted
/// (the branch keeps them alive) left the previous server's rows on screen under
/// the new connection's name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/presentation/readarr_activity_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_history_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/fake_secure_settings_store.dart';

const _home = ServiceInstance(
  id: 'readarr',
  service: ServiceKey.readarr,
  url: 'http://readarr.lan:8787',
  credential: 'key-home',
);

const _kids = ServiceInstance(
  id: 'readarr-kids11111',
  service: ServiceKey.readarr,
  url: 'http://readarr-kids.lan:8787',
  credential: 'key-kids',
);

/// A Readarr that answers with the name of the connection it is.
class _NamedReadarr extends ReadarrService {
  _NamedReadarr(this.name) : super(FakeApiClient());

  final String name;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => [
    {'title': 'Queued on $name'},
  ];

  @override
  Future<List<dynamic>> getAllMissing({
    Map<String, dynamic>? queryParameters,
  }) async => [
    {'title': 'Missing on $name'},
  ];

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => [
    {
      'id': 1,
      'eventType': 'grabbed',
      'sourceTitle': 'History of $name',
      'date': '2026-10-19T10:00:00Z',
    },
  ];
}

Future<ProviderContainer> _pump(WidgetTester tester, Widget screen) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await tester.runAsync(SharedPreferences.getInstance);
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith(
        (ref) => const SettingsModel(instances: [_home, _kids]),
      ),
      initialActiveInstancesProvider.overrideWithValue(const {}),
      sharedPreferencesProvider.overrideWithValue(prefs!),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      // Rebuilt when the lens moves, as the real service is.
      readarrServiceProvider.overrideWith(
        (ref) => _NamedReadarr(
          ref.watch(activeInstanceProvider(ServiceKey.readarr))!.id,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(500, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _moveLens(WidgetTester tester, ProviderContainer container) async {
  await container
      .read(activeInstancesProvider.notifier)
      .select(ServiceKey.readarr, _kids.id);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the queue shows the rows of the connection the lens moved to', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      const ReadarrActivityScreen(mode: ReadarrActivityMode.queue),
    );
    expect(find.text('Queued on readarr'), findsOneWidget);

    await _moveLens(tester, container);

    expect(find.text('Queued on readarr-kids11111'), findsOneWidget);
    expect(find.text('Queued on readarr'), findsNothing);
  });

  testWidgets('the wanted tab shows the rows of the connection the lens moved '
      'to', (tester) async {
    final container = await _pump(
      tester,
      const ReadarrActivityScreen(mode: ReadarrActivityMode.wanted),
    );
    expect(find.text('Missing on readarr'), findsOneWidget);

    await _moveLens(tester, container);

    expect(find.text('Missing on readarr-kids11111'), findsOneWidget);
    expect(find.text('Missing on readarr'), findsNothing);
  });

  testWidgets('History shows the rows of the connection the lens moved to', (
    tester,
  ) async {
    final container = await _pump(tester, const ReadarrHistoryScreen());
    expect(find.textContaining('History of readarr'), findsOneWidget);
    expect(find.textContaining('readarr-kids11111'), findsNothing);

    await _moveLens(tester, container);

    expect(find.textContaining('History of readarr-kids11111'), findsOneWidget);
  });
}
