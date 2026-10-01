import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_rss_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/presentation/reporting/truenas_reporting_screen.dart';

import '../../test_helpers/profiles/profiles.dart';
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

/// Where the last tap landed, as the router saw it: path and query.
Uri? _landedOn;

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override>? overrides,
}) async {
  _landedOn = null;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: child),
      ),
      GoRoute(
        path: '/settings/service/:id',
        builder: (_, state) {
          _landedOn = state.uri;
          return Scaffold(body: Text('Form ${state.pathParameters['id']}'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides:
          overrides ??
          [
            currentSettingsProvider.overrideWith(
              (ref) => settingsWithServices(const [
                ServiceKey.radarr,
                ServiceKey.qbittorrent,
              ]),
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

/// The ink button carrying [label]: the primary action.
Finder _filled(String label) => find.widgetWithText(FilledButton, label);

/// The text button carrying [label]: the secondary action.
Finder _text(String label) => find.widgetWithText(TextButton, label);

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
  group('ServiceOfflineState', () {
    testWidgets('the plain leaf says "did not answer" in red, never the lamp', (
      tester,
    ) async {
      await _pump(
        tester,
        ServiceOfflineState(
          serviceName: 'SABnzbd',
          accent: ServiceKey.sabnzbd.accent,
          onRetry: () {},
        ),
      );

      expect(find.text('SABnzbd did not answer'), findsOneWidget);
      final scheme = AppTheme.darkTheme().colorScheme;
      expect(_glyphColor(tester), statusToneColor(scheme, StatusTone.error));
      // The service's light is the neutral lamp, which said nothing about the
      // one state red exists for.
      expect(_glyphColor(tester), isNot(ServiceKey.sabnzbd.accent));
    });

    testWidgets('P7: a SABnzbd that answers only at home is red away', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p7,
        child: const SabnzbdScreen(showAppBar: false),
      );

      expect(find.text('SABnzbd did not answer'), findsOneWidget);
      expect(
        _glyphColor(tester),
        statusToneColor(AppTheme.darkTheme().colorScheme, StatusTone.error),
      );

      await harness.unmount(tester);
    });
  });

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
      // The remedy is the verb on the way into the form, not "Settings", and
      // it leads: the same key can only be refused again, so no Retry.
      expect(_filled('Paste the key again'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      await tester.tap(find.text('Paste the key again'));
      await tester.pumpAndSettle();
      expect(find.text('Form radarr'), findsOneWidget);
    });

    testWidgets(
      'a certificate leads with its remedy and keeps Retry after it',
      (tester) async {
        var retried = 0;
        await _pump(
          tester,
          ServiceOfflineState.failure(
            service: ServiceKey.radarr,
            error: const ClassifiedFailure(ServiceFailureReason.tls),
            onRetry: () => retried++,
          ),
        );

        expect(_filled('Check the certificate'), findsOneWidget);
        expect(_text('Retry'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        expect(retried, 1);
      },
    );

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
      // The headline in the state's tone: the red words, never contracted.
      expect(label('The server did not answer'), red);

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
      expect(label('The server answered but refused the key'), amber);
      expect(find.text('The server did not answer'), findsNothing);
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

      expect(
        find.text('The request to the server did not complete'),
        findsOneWidget,
      );
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

  group('the remedy leads', () {
    testWidgets('AppErrorState: a refused key offers the key, and no Retry', (
      tester,
    ) async {
      await _pump(
        tester,
        AppErrorState(
          serviceName: 'Radarr',
          error: _status(401),
          onRetry: () {},
        ),
      );

      expect(find.text('Radarr answered but refused the key'), findsOneWidget);
      expect(_filled('Paste the key again'), findsOneWidget);
      // The same key can only be refused again.
      expect(find.text('Retry'), findsNothing);

      await tester.tap(find.text('Paste the key again'));
      await tester.pumpAndSettle();
      // The lens connection's own form.
      expect(_landedOn?.path, '/settings/service/radarr');
      expect(_landedOn?.queryParameters['i'], isNotEmpty);
    });

    testWidgets('AppErrorState: an API not at the address leads with the '
        'address, and Retry follows', (tester) async {
      var retried = 0;
      await _pump(
        tester,
        AppErrorState(
          serviceName: 'Radarr',
          error: _status(404),
          onRetry: () => retried++,
        ),
      );

      expect(_filled('Check the address'), findsOneWidget);
      expect(_text('Retry'), findsOneWidget);
      // The remedy first, for the eye and for the screen reader.
      expect(
        tester.getTopLeft(find.text('Check the address')).dx,
        lessThan(tester.getTopLeft(find.text('Retry')).dx),
      );
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    testWidgets(
      'AppErrorState: a refused sign-in keeps Retry, a ban runs out',
      (tester) async {
        await _pump(
          tester,
          AppErrorState(
            serviceName: 'qBittorrent',
            error: _status(403),
            onRetry: () {},
          ),
        );

        expect(_filled('Sign in again'), findsOneWidget);
        expect(_text('Retry'), findsOneWidget);
      },
    );

    testWidgets('AppErrorState: nothing answered, so Retry is the remedy', (
      tester,
    ) async {
      await _pump(
        tester,
        AppErrorState(serviceName: 'Radarr', error: _refused(), onRetry: () {}),
      );

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.text('Paste the key again'), findsNothing);
    });

    testWidgets('AppErrorState: a state that cannot name the service keeps '
        'Retry, and opens no form', (tester) async {
      await _pump(tester, AppErrorState(error: _status(401), onRetry: () {}));

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Paste the key again'), findsNothing);
    });

    testWidgets('InlineErrorRetry: a section Radarr refused offers the key in '
        'place of Retry', (tester) async {
      final error = _status(401);
      await _pump(
        tester,
        InlineErrorRetry(
          message: sectionFailureMessage(
            ServiceKey.radarr,
            error,
            consequence: 'its queue is not shown',
          ),
          error: error,
          onRetry: () {},
        ),
      );

      expect(_text('Paste the key again'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.tap(find.text('Paste the key again'));
      await tester.pumpAndSettle();
      expect(find.text('Form radarr'), findsOneWidget);
    });

    testWidgets('InlineErrorRetry: a certificate keeps both verbs, the remedy '
        'first, under the sentence', (tester) async {
      const error = ClassifiedFailure(ServiceFailureReason.tls);
      await _pump(
        tester,
        InlineErrorRetry(
          message: sectionFailureMessage(
            ServiceKey.radarr,
            error,
            consequence: 'its queue is not shown',
          ),
          error: error,
          onRetry: () {},
        ),
      );

      expect(_text('Check the certificate'), findsOneWidget);
      expect(_text('Retry'), findsOneWidget);
      final sentence = tester.getBottomLeft(
        find.textContaining('Radarr has a certificate'),
      );
      expect(
        tester.getTopLeft(find.text('Check the certificate')).dy,
        greaterThanOrEqualTo(sentence.dy),
      );
      expect(
        tester.getTopLeft(find.text('Check the certificate')).dx,
        lessThan(tester.getTopLeft(find.text('Retry')).dx),
      );
      // Each verb keeps the touch floor.
      for (final label in ['Check the certificate', 'Retry']) {
        expect(tester.getSize(_text(label)).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('InlineErrorRetry: the fixed-height slot holds two verbs', (
      tester,
    ) async {
      Future<double> slotFor(Object error) async {
        await _pump(
          tester,
          // Wide enough for both verbs on one line in the test font, whose
          // glyphs are all a full em: a real phone fits them in 360.
          SizedBox(
            width: 600,
            child: InlineErrorRetry.fixedHeight(
              message: sectionFailureMessage(
                ServiceKey.radarr,
                error,
                consequence: 'this row is missing',
              ),
              error: error,
              onRetry: () {},
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        return tester.getSize(find.byType(InlineErrorRetry)).height;
      }

      final one = await slotFor(_refused());
      final two = await slotFor(
        const ClassifiedFailure(ServiceFailureReason.notFound),
      );
      expect(_text('Check the address'), findsOneWidget);
      expect(_text('Retry'), findsOneWidget);
      // A carousel row that fails does not jump for having two verbs.
      expect(two, one);
    });

    testWidgets('the remedy opens the connection the lens rests on', (
      tester,
    ) async {
      // P1 has two Radarrs. With the lens on the 4K one, its refused key is
      // pasted into the 4K form, not into the first connection's.
      final harness = await ProfileHarness.start(
        Profiles.p1.withLens(ServiceKey.radarr, WorldIds.radarr4k),
      );
      await _pump(
        tester,
        AppErrorState(
          serviceName: 'Radarr',
          error: _status(401),
          onRetry: () {},
        ),
        overrides: harness.overrides,
      );

      await tester.tap(find.text('Paste the key again'));
      await tester.pumpAndSettle();
      expect(_landedOn?.queryParameters['i'], WorldIds.radarr4k);
    });

    testWidgets('P1, TrueNAS refused the key: its reporting page offers the '
        'key, with no per-screen wiring', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p1.withBehaviour(
          WorldIds.truenas,
          ConnectionBehaviour.refusesKey,
        ),
        child: const TrueNasReportingScreen(),
      );

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Paste the key again'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P7, qBittorrent refused the sign-in: its RSS sections lead '
        'with the sign-in and keep Retry', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p7,
        child: const QbittorrentRssScreen(),
      );

      expect(find.byType(InlineErrorRetry), findsNWidgets(2));
      expect(_text('Sign in again'), findsNWidgets(2));
      expect(_text('Retry'), findsNWidgets(2));

      await harness.unmount(tester);
    });
  });
}
