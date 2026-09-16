import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_async_body.dart';

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
  });
}
