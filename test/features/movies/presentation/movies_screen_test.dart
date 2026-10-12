import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/settings_scope.dart';

Future<FakeApiClient> _pump(WidgetTester tester, FakeApiClient api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices(const [ServiceKey.radarr]),
        ),
        radarrServiceProvider.overrideWith((ref) => RadarrService(api)),
        radarrQueueSnapshotProvider.overrideWith(
          (ref) async => throw Exception('queue down'),
        ),
        serviceKpiProvider.overrideWith(
          (ref, service) async => const <ServiceKpi>[],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        home: const MoviesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('a Radarr that does not answer shows the fault, not an empty '
      'library', (tester) async {
    final api = FakeApiClient()
      ..getException = DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/v3/movie'),
        reason: 'Connection refused',
      );
    await _pump(tester, api);

    // "No items found" was the whole wall for a server that never answered.
    expect(find.text('No items found'), findsNothing);
    // The service's own leaf, in plain words: who, where, and the two ways out.
    expect(find.byType(ServiceOfflineState), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expect(find.text('Radarr did not answer'), findsOneWidget);
    expect(find.text('radarr.test'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    // Never the exception class or the library's own message.
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('solved by the library'), findsNothing);

    // The Retry is live and asks again: once per tap, not ten times behind a
    // backoff.
    final before = api.getCallCount;
    api.getException = null;
    api.getResponseData = <dynamic>[];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.getCallCount, greaterThan(before));
    expect(find.byType(ServiceOfflineState), findsNothing);
    expect(find.text('No items found'), findsOneWidget);
  });

  testWidgets('a Radarr that answers and refuses the key is an amber fault, '
      'not "did not answer"', (tester) async {
    final api = FakeApiClient()
      ..getException = DioException(
        requestOptions: RequestOptions(path: '/api/v3/movie'),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/v3/movie'),
          statusCode: 401,
        ),
      );
    await _pump(tester, api);

    expect(find.text('Radarr answered but refused the key'), findsOneWidget);
    expect(find.text('Radarr did not answer'), findsNothing);
    expect(
      find.text(
        "Radarr answered, and does not accept this API key. Copy it again from Radarr's own settings.",
      ),
      findsOneWidget,
    );
  });
}
