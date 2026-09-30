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
        find.textContaining('Nothing answered at this address.'),
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

      expect(find.text('Radarr answered but refused the key'), findsOneWidget);
      expect(
        find.text(
          "Radarr answered, and does not accept this API key. Copy it again "
          "from Radarr's own settings.",
        ),
        findsOneWidget,
      );
      final scheme = AppTheme.darkTheme().colorScheme;
      expect(_glyphColor(tester), statusToneColor(scheme, StatusTone.warning));
      // The remedy is the verb on the way into the form, not "Settings".
      expect(find.text('Paste the key again'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
      await tester.tap(find.text('Paste the key again'));
      await tester.pumpAndSettle();
      expect(find.text('Form radarr'), findsOneWidget);
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

      expect(find.text('Radarr answered with an error'), findsOneWidget);
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
          RegExp(r'^Radarr did not answer\. radarr\.test\. Nothing answered'),
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

      // The classification's headline, never "Couldn't load Radarr".
      expect(find.text('Radarr did not answer'), findsOneWidget);
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
              matching: find.byType(Icon),
            ),
          )
          .color!;
      Color? label(String text) =>
          tester.widget<Text>(find.text(text)).style?.color;

      await _pump(tester, AppErrorState(error: _refused()));
      final red = statusToneColor(scheme, StatusTone.error);
      expect(glyph(), red);
      // The red words, in red, and never contracted.
      expect(label('Did not answer'), red);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, AppErrorState(error: _status(401)));
      expect(
        find.text(
          'The server answered and refused the saved credentials. Check them in '
          'Settings.',
        ),
        findsOneWidget,
      );
      final amber = statusToneColor(scheme, StatusTone.warning);
      expect(glyph(), amber);
      expect(label('Refused the key'), amber);
      expect(find.text('Did not answer'), findsNothing);
    });

    testWidgets('no red well: the glyph alone carries the tone', (
      tester,
    ) async {
      final scheme = AppTheme.darkTheme().colorScheme;
      await _pump(tester, AppErrorState(error: _refused()));

      // The Presence Rule: no red fill behind a fault. The error container
      // was a red disc behind every failure in the app.
      final fills = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(AppErrorState),
              matching: find.byType(Container),
            ),
          )
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .whereType<Color>();
      expect(fills, isNot(contains(scheme.errorContainer)));
    });

    testWidgets('a failure nobody can attribute is not painted as silence', (
      tester,
    ) async {
      final scheme = AppTheme.darkTheme().colorScheme;
      await _pump(tester, AppErrorState(error: StateError('parser')));

      expect(find.text('Did not complete'), findsOneWidget);
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byType(AppErrorState),
                matching: find.byType(Icon),
              ),
            )
            .color,
        statusToneColor(scheme, StatusTone.warning),
      );
    });
  });
}
