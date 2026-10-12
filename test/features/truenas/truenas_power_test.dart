import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/truenas/data/system_api.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';

typedef _Call = ({String method, List<dynamic> params, bool asJob});

class _RecordingClient extends TrueNasWsClient {
  _RecordingClient() : super(baseUrl: 'https://nas.local', apiKey: 'key');

  final List<_Call> calls = [];

  @override
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    calls.add((method: method, params: params, asJob: false));
    return null;
  }

  @override
  Future<dynamic> callJob(
    String method, [
    List<dynamic> params = const [],
    TrueNasJobProgress? onProgress,
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 1),
  ]) async {
    calls.add((method: method, params: params, asJob: true));
    return null;
  }
}

void main() {
  group('decision 38: power', () {
    test('shutdown and reboot name the two RPCs and carry a reason', () async {
      final client = _RecordingClient();
      final api = TrueNasSystemApi(client);

      await api.shutdown();
      await api.reboot();

      expect(client.calls.map((c) => c.method), [
        'system.shutdown',
        'system.reboot',
      ]);
      // SCALE 25.04 made `reason` mandatory, and it is what lands in the host's
      // own shutdown log: an unexplained reboot in the audit trail is the thing
      // this argument exists to prevent.
      for (final call in client.calls) {
        expect(call.params.first, isA<String>());
        expect((call.params.first as String).isNotEmpty, isTrue);
      }
    });

    test('neither is issued as a job', () async {
      // A job is polled with `core.get_jobs` until it reaches a terminal state.
      // Nothing can poll a host that is powering off, so the poll would spin
      // until its own timeout and then report failure.
      final client = _RecordingClient();
      await TrueNasSystemApi(client).shutdown();

      expect(client.calls.single.asJob, isFalse);
    });
  });

  group('the detached action runner', () {
    testWidgets('reports without waiting for a reply that never comes', (
      tester,
    ) async {
      // The whole point: `runTrueNasAction` awaits before it says anything, so
      // on a call whose socket dies mid-flight the only reachable outcome is
      // the red failure snack. This one must speak while the future is still
      // unresolved.
      final never = Completer<void>();
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      runTrueNasDetachedAction(
        ctx,
        action: () => never.future,
        message: 'Shutting down nas…',
      );
      await tester.pump();

      expect(find.text('Shutting down nas…'), findsOneWidget);
      expect(never.isCompleted, isFalse);
    });

    testWidgets('a dead socket does not surface as a failure', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      runTrueNasDetachedAction(
        ctx,
        action: () async => throw const TrueNasException('Connection closed'),
        message: 'Rebooting nas…',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Present tense, and nothing else: the error is indistinguishable from
      // success here, so claiming either would be a guess.
      expect(find.text('Rebooting nas…'), findsOneWidget);
      expect(find.textContaining('Could not'), findsNothing);
      expect(find.textContaining('Failed'), findsNothing);
    });
  });
}
