import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/presentation/reporting/truenas_reporting_screen.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_async_body.dart';

import '../../test_helpers/profiles/profiles.dart';
import '../../test_helpers/settings_scope.dart';

Future<void> _pump(WidgetTester tester, AsyncValue<String> value) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: TrueNasAsyncBody<String>(
            value: value,
            onRetry: () {},
            data: (d) => Text(d),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('the TrueNAS connection well', () {
    testWidgets('"not configured" is an invitation, not a failure', (
      tester,
    ) async {
      // `truenasClientProvider` throws this before it opens a socket, so every
      // section used to render a generic error card with a Retry that could
      // never succeed — the only service in the app that answered its own
      // setup screen with an alarm.
      await _pump(
        tester,
        AsyncValue.error(
          const TrueNasException('TrueNAS not configured'),
          StackTrace.empty,
        ),
      );
      await tester.pump();

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
    });

    testWidgets('a cold state scrolls inside a short desktop pane', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 240);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(
        tester,
        AsyncValue.error(
          const TrueNasException('TrueNAS not configured'),
          StackTrace.empty,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsOneWidget);
    });

    testWidgets('a host that did not answer reads as offline', (tester) async {
      await _pump(
        tester,
        AsyncValue.error(
          const TrueNasException(
            'connection refused',
            reason: ServiceFailureReason.unreachable,
          ),
          StackTrace.empty,
        ),
      );
      await tester.pump();

      expect(find.byType(ServiceOfflineState), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
    });

    testWidgets('a NAS that went quiet keeps its last readout under a band', (
      tester,
    ) async {
      // The state Riverpod holds when a provider that had answered fails on a
      // later poll. The offline well used to replace the pool with "did not
      // answer" the moment one poll failed.
      final quiet = AsyncValue<String>.error(
        const TrueNasException(
          'connection refused',
          reason: ServiceFailureReason.unreachable,
        ),
        StackTrace.empty,
        // ignore: invalid_use_of_internal_member
      ).copyWithPrevious(const AsyncValue.data('tank DEGRADED'));

      await _pump(tester, quiet);
      await tester.pump();

      expect(find.text('tank DEGRADED'), findsOneWidget);
      expect(find.byType(FaultBand), findsOneWidget);
      expect(
        tester.widget<FaultBand>(find.byType(FaultBand)).tone,
        StatusTone.error,
      );
      expect(find.byType(ServiceOfflineState), findsNothing);
    });

    testWidgets('an http:// address asks for https, and offers its remedy, not '
        'Retry', (tester) async {
      // The client refused to send the key, so a Retry could only be refused
      // again: the one action is the remedy, into the form where the address
      // lives.
      Uri? landedOn;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: TrueNasAsyncBody<String>(
                value: AsyncValue.error(
                  const TrueNasInsecureTransportException(),
                  StackTrace.empty,
                ),
                onRetry: () {},
                data: (d) => Text(d),
              ),
            ),
          ),
          GoRoute(
            path: '/settings/service/:service',
            builder: (_, state) {
              landedOn = state.uri;
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: await settingsScopeOverrides(
            configured: const [ServiceKey.truenas],
          ),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(find.text('TrueNAS needs an https:// address'), findsOneWidget);
      expect(
        find.text(TrueNasInsecureTransportException.explanation),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.byType(ServiceOfflineState), findsNothing);
      expect(find.byType(NotConfiguredPlaceholder), findsNothing);

      expect(find.text('Open Settings'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Change the address'),
        findsOneWidget,
      );
      await tester.tap(find.text('Change the address'));
      await tester.pumpAndSettle();
      // The connection the lens rests on, inside TrueNAS's own form.
      expect(landedOn?.path, ServiceRoutes.settingsFor(ServiceKey.truenas));
      expect(landedOn?.queryParameters['i'], isNotEmpty);
    });

    testWidgets('a TLS refusal is the same fact as an unreachable host', (
      tester,
    ) async {
      await _pump(
        tester,
        AsyncValue.error(
          const TrueNasException(
            'bad certificate',
            reason: ServiceFailureReason.tls,
          ),
          StackTrace.empty,
        ),
      );
      await tester.pump();

      expect(find.byType(ServiceOfflineState), findsOneWidget);
    });

    testWidgets('a server that answered and refused keeps the error card', (
      tester,
    ) async {
      // The host is up and talking: "did not answer" would be a lie, and the
      // message it sent is the actionable part.
      await _pump(
        tester,
        AsyncValue.error(
          const TrueNasException(
            'Invalid API key',
            reason: ServiceFailureReason.unauthorized,
          ),
          StackTrace.empty,
        ),
      );
      await tester.pump();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.byType(ServiceOfflineState), findsNothing);
      expect(find.byType(NotConfiguredPlaceholder), findsNothing);
    });

    testWidgets('an error carrying no reason at all still shows something', (
      tester,
    ) async {
      await _pump(
        tester,
        AsyncValue.error(Exception('boom'), StackTrace.empty),
      );
      await tester.pump();

      expect(find.byType(AppErrorState), findsOneWidget);
    });

    testWidgets('data goes straight through', (tester) async {
      await _pump(tester, const AsyncValue.data('tank'));
      await tester.pump();

      expect(find.text('tank'), findsOneWidget);
    });

    testWidgets('the loading state says which service it is loading', (
      tester,
    ) async {
      await _pump(tester, const AsyncValue<String>.loading());
      await tester.pump();

      expect(find.bySemanticsLabel('Loading TrueNAS'), findsOneWidget);
    });

    testWidgets('the inline form nests no second pull-to-refresh', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TrueNasAsyncBody<String>.inline(
                value: const AsyncValue.data('tank'),
                onRetry: () {},
                data: (d) => Text(d),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(RefreshIndicator), findsNothing);
      expect(find.text('tank'), findsOneWidget);
    });

    testWidgets('P1 with an http:// TrueNAS: the reporting page offers to '
        'change the address, and no Retry', (tester) async {
      // The app's own TrueNAS client refuses the address before it dials.
      final harness = await pumpWithProfile(
        tester,
        Profiles.p1.withConnection(
          ProfileConnection(
            WorldConnections.truenas.instance.copyWith(
              url: 'http://nas.home.arpa',
            ),
          ),
        ),
        child: const TrueNasReportingScreen(),
      );

      expect(find.text('TrueNAS needs an https:// address'), findsOneWidget);
      expect(find.text('Change the address'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
      expect(find.text('Retry'), findsNothing);

      await harness.unmount(tester);
    });
  });
}
