import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/settings_scope.dart';

DioException _refused() => DioException.connectionError(
  requestOptions: RequestOptions(path: '/api/v3/movie'),
  reason: 'Connection refused',
);

DioException _status(int code) => DioException(
  requestOptions: RequestOptions(path: '/api/v3/movie'),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/v3/movie'),
    statusCode: code,
  ),
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: child),
      ),
      GoRoute(
        path: '/settings/service/:id',
        builder: (_, state) =>
            Scaffold(body: Text('Form ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices(const [ServiceKey.radarr]),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color _glyphColor(WidgetTester tester) => tester
    .widget<Icon>(
      find
          .descendant(
            of: find.byType(ServiceOfflineState),
            matching: find.byType(Icon),
          )
          .first,
    )
    .color!;

void main() {
  group('ServiceOfflineState.failure', () {
    testWidgets('a server that did not answer: red, its address, Retry and '
        'Settings — and no exception text', (tester) async {
      await _pump(
        tester,
        ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: _refused(),
          onRetry: () {},
        ),
      );

      expect(find.text('Radarr did not answer'), findsOneWidget);
      expect(find.text('radarr.test'), findsOneWidget);
      expect(
        find.textContaining('Could not reach the server.'),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('solved by the library'), findsNothing);

      final scheme = AppTheme.darkTheme().colorScheme;
      expect(_glyphColor(tester), statusToneColor(scheme, StatusTone.error));

      // Settings goes to this service's own connection form.
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Form radarr'), findsOneWidget);
    });

    testWidgets('a refused key is an amber fault in the connection form\'s '
        'words', (tester) async {
      await _pump(
        tester,
        ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: _status(401),
          onRetry: () {},
        ),
      );

      expect(find.text('Radarr: API key rejected'), findsOneWidget);
      expect(
        find.text('Reached Radarr, which rejected the API key.'),
        findsOneWidget,
      );
      final scheme = AppTheme.darkTheme().colorScheme;
      expect(_glyphColor(tester), statusToneColor(scheme, StatusTone.warning));
    });

    testWidgets('a 5xx is a fault too, never "did not answer"', (tester) async {
      await _pump(
        tester,
        ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: _status(500),
          onRetry: () {},
        ),
      );

      expect(find.text('Radarr: Answered with an error'), findsOneWidget);
      expect(find.text('Radarr did not answer'), findsNothing);
    });

    testWidgets('speaks one sentence with the address in it', (tester) async {
      await _pump(
        tester,
        ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: _refused(),
          onRetry: () {},
        ),
      );

      expect(
        find.semantics.byLabel(
          RegExp(r'^Radarr did not answer\. radarr\.test\. Could not reach'),
        ),
        findsOneWidget,
      );
    });
  });

  group('AppErrorState', () {
    testWidgets('prints the cause in plain words, never the exception', (
      tester,
    ) async {
      await _pump(
        tester,
        AppErrorState(serviceName: 'Radarr', error: _refused(), onRetry: () {}),
      );

      expect(find.text("Couldn't load Radarr"), findsOneWidget);
      expect(
        find.textContaining('Nothing answered at the saved address.'),
        findsOneWidget,
      );
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('solved by the library'), findsNothing);
    });

    testWidgets('red for silence, amber for a server that answered', (
      tester,
    ) async {
      final scheme = AppTheme.darkTheme().colorScheme;
      Color glyph() => tester
          .widget<Icon>(
            find.descendant(
              of: find.byType(AppErrorState),
              matching: find.byIcon(Icons.error_outline_rounded),
            ),
          )
          .color!;

      await _pump(tester, AppErrorState(error: _refused()));
      expect(
        glyph(),
        statusToneColor(
          scheme,
          StatusTone.error,
          surface: scheme.errorContainer,
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, AppErrorState(error: _status(401)));
      expect(
        find.text('The server answered and rejected the saved credentials.'),
        findsOneWidget,
      );
      expect(
        glyph(),
        statusToneColor(
          scheme,
          StatusTone.warning,
          surface: scheme.surface,
          tintAlpha: 0.16,
        ),
      );
    });
  });
}
