import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

/// The rule: **nothing the service already said is thrown away because it
/// stopped answering.**
///
/// This widget used to call `value.when(...)`, the one shape of the Riverpod
/// API that cannot see a retained value, so an `AsyncError` carrying the
/// previous data routed straight to a red leaf, and the readout the user opened
/// the app to look at was discarded at the widget boundary, after the state
/// layer had gone to the trouble of keeping it.
///
/// `copyWithPrevious` is exactly the state Riverpod itself produces when a
/// provider that had already answered fails on a later poll. Reaching for it
/// here is deliberate: driving a real provider to the same state means letting
/// Riverpod 3's automatic retry run, which never settles, so the test would
/// hang rather than assert. The `ignore` is the cost of naming the state
/// directly instead.
// ignore: invalid_use_of_internal_member
AsyncValue<T> _failedOver<T>(T retained, {Object? error}) {
  return AsyncValue<T>.error(
    error ?? Exception('connection refused'),
    StackTrace.empty,
    // ignore: invalid_use_of_internal_member
  ).copyWithPrevious(AsyncValue<T>.data(retained));
}

Future<void> _pump(WidgetTester tester, AsyncValue<String> value) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AsyncValueWidget<String>(
          value: value,
          serviceName: 'TrueNAS',
          onRetry: () {},
          data: (data) => Text(data),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('an error over retained data keeps the data, under a band', (
    tester,
  ) async {
    final failed = _failedOver('tank DEGRADED 78%');
    expect(failed.hasError, isTrue);
    expect(failed.hasValue, isTrue);

    await _pump(tester, failed);

    // The last thing the box said before it went dark is precisely what the
    // operator came for.
    expect(find.text('tank DEGRADED 78%'), findsOneWidget);
    expect(find.byType(FaultBand), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
  });

  testWidgets('the band over retained data is red only for silence', (
    tester,
  ) async {
    await _pump(
      tester,
      _failedOver(
        'tank DEGRADED 78%',
        error: const SocketException('Connection refused'),
      ),
    );
    expect(
      tester.widget<FaultBand>(find.byType(FaultBand)).tone,
      StatusTone.error,
    );
    expect(find.textContaining('TrueNAS did not answer'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      _failedOver(
        'tank DEGRADED 78%',
        error: const ClassifiedFailure(ServiceFailureReason.unauthorized),
      ),
    );
    // Answered and refused: amber, and still the readout below.
    expect(
      tester.widget<FaultBand>(find.byType(FaultBand)).tone,
      StatusTone.warning,
    );
    expect(
      find.textContaining('TrueNAS answered but refused the key'),
      findsOneWidget,
    );
    expect(find.text('tank DEGRADED 78%'), findsOneWidget);
  });

  testWidgets('the retained readout is not dimmed', (tester) async {
    // Rule 3 of the failure grammar: dimming means *not configured* everywhere
    // else on this canvas, and the two states need opposite answers: "go set
    // this up" against "this is what it said last".
    await _pump(tester, _failedOver('tank DEGRADED 78%'));

    expect(
      find.ancestor(
        of: find.text('tank DEGRADED 78%'),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
  });

  // A reload is the provider building again because something it watches
  // changed. Over a healthy readout it used to empty the page to a skeleton
  // until the new answer came back. Driven through real providers: a figure
  // derived from a source that changes under it.
  testWidgets('a reload over data keeps the data until the new answer', (
    tester,
  ) async {
    final source = NotifierProvider<_Count, int>(_Count.new);
    var pending = Completer<void>()..complete();
    final derived = FutureProvider<String>((ref) async {
      final count = ref.watch(source);
      await pending.future;
      return '$count pools';
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => AsyncValueWidget<String>(
                value: ref.watch(derived),
                serviceName: 'TrueNAS',
                onRetry: () => ref.invalidate(derived),
                skeleton: const Text('skeleton'),
                data: (data) => Text(data),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('2 pools'), findsOneWidget);

    pending = Completer<void>();
    container.read(source.notifier).bump();
    await tester.pump();

    expect(container.read(derived).isReloading, isTrue);
    expect(find.text('2 pools'), findsOneWidget);
    expect(find.text('skeleton'), findsNothing);

    pending.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('3 pools'), findsOneWidget);
  });

  testWidgets('a cold failure still gets the full-page leaf', (tester) async {
    // The case `AppErrorState` is actually for: nothing has answered in this
    // session, so there is no readout behind the band to keep.
    await _pump(
      tester,
      AsyncValue<String>.error(
        Exception('connection refused'),
        StackTrace.empty,
      ),
    );

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.byType(FaultBand), findsNothing);
  });

  group('a section of a page', () {
    Future<void> pumpSection(WidgetTester tester, AsyncValue<String> value) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AsyncValueWidget<String>.section(
                value: value,
                service: ServiceKey.plex,
                consequence: 'what the server says about itself is not shown',
                onRetry: () {},
                data: (data) => Text(data),
              ),
            ),
          ),
        );

    testWidgets('a cold failure is one line, not the page-sized leaf', (
      tester,
    ) async {
      await pumpSection(
        tester,
        AsyncValue<String>.error(
          const SocketException('connection refused'),
          StackTrace.empty,
        ),
      );

      expect(find.byType(AppErrorState), findsNothing);
      expect(find.byType(InlineErrorRetry), findsOneWidget);
      expect(
        find.textContaining(
          ', so what the server says about itself is not shown.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failure over retained data keeps it under a band', (
      tester,
    ) async {
      await pumpSection(tester, _failedOver('Plex Media Server'));

      expect(find.text('Plex Media Server'), findsOneWidget);
      expect(find.byType(FaultBand), findsOneWidget);
      expect(find.byType(InlineErrorRetry), findsNothing);
    });
  });

  test('lastReadUnderBand keeps the last read only under a band', () {
    final failed = _failedOver('queue');
    expect(lastReadUnderBand(failed, banded: true), isA<AsyncData<String>>());
    expect(lastReadUnderBand(failed, banded: true).value, 'queue');
    expect(lastReadUnderBand(failed, banded: false).hasError, isTrue);
    final cold = AsyncValue<String>.error(Exception('x'), StackTrace.empty);
    expect(lastReadUnderBand(cold, banded: true).hasError, isTrue);
  });

  group('showsLastReadUnderBand says what the widget draws', () {
    Future<Object> closedClientError() async {
      final dio = Dio()..close();
      try {
        await dio.get<dynamic>('http://nas.home.arpa:7878/api/v3/movie');
      } catch (error) {
        return error;
      }
      fail('a closed client sent the request');
    }

    Future<void> expectAgrees(
      WidgetTester tester,
      AsyncValue<String> value, {
      required bool band,
    }) async {
      await _pump(tester, value);
      expect(find.byType(FaultBand), band ? findsOneWidget : findsNothing);
      expect(showsLastReadUnderBand(value), band);
    }

    testWidgets('a failure over a read is a band', (tester) async {
      await expectAgrees(tester, _failedOver('queue'), band: true);
    });

    testWidgets('a read that is current is not', (tester) async {
      await expectAgrees(
        tester,
        const AsyncValue<String>.data('queue'),
        band: false,
      );
    });

    testWidgets('a failure with nothing read is not', (tester) async {
      await expectAgrees(
        tester,
        AsyncValue<String>.error(Exception('x'), StackTrace.empty),
        band: false,
      );
    });

    testWidgets('a first load is not', (tester) async {
      await expectAgrees(
        tester,
        const AsyncValue<String>.loading(),
        band: false,
      );
    });

    testWidgets('a client closed under the read is not', (tester) async {
      final error = await closedClientError();

      await expectAgrees(
        tester,
        _failedOver('queue', error: error),
        band: false,
      );
    });
  });

  testWidgets('"not configured" still wins over everything', (tester) async {
    // A service with no URL saved is not an outage and must never get the
    // outage band. The answer there is "go set this up".
    final failed = _failedOver(
      'stale',
      error: const ServiceNotConfigured(ServiceKey.truenas),
    );
    await _pump(tester, failed);

    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    expect(find.byType(FaultBand), findsNothing);
  });

  testWidgets('a retained value that is empty falls back to the leaf', (
    tester,
  ) async {
    // Keeping an empty list under a band would draw a band over nothing, which
    // says less than the leaf does.
    final failed = _failedOver(<String>[]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncValueWidget<List<String>>(
            value: failed,
            serviceName: 'TrueNAS',
            onRetry: () {},
            isEmpty: (data) => data.isEmpty,
            data: (data) => Text(data.join()),
          ),
        ),
      ),
    );

    expect(find.byType(AppErrorState), findsOneWidget);
  });

  // OPS-05, the widget's half. qBittorrent's own providers fail fast
  // (`noProviderRetry`), but most reads in the app keep Riverpod's default
  // retry, and while it runs the state is `AsyncLoading(value: last, error)`:
  // `when` drew that as a reload, so the list became a spinner, and a poll that
  // invalidates every three seconds cancels the retry timer before the tenth
  // attempt could settle it. Driven here through a real provider under the
  // default policy, with the list's own poll, rather than a hand-built state.
  group('a failure over a retained value, while Riverpod retries', () {
    late bool down;
    late FutureProvider<List<String>> torrents;
    late ProviderContainer container;

    setUp(() {
      down = false;
      torrents = FutureProvider<List<String>>((ref) async {
        if (down) throw const SocketException('Connection refused');
        return const ['Ubuntu.ISO', 'Debian.ISO'];
      });
      // No `retry:` anywhere: the default policy is the condition under test.
      container = ProviderContainer();
    });

    Future<void> pumpList(WidgetTester tester) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => AsyncValueWidget<List<String>>(
                value: ref.watch(torrents),
                serviceName: 'qBittorrent',
                onRetry: () => ref.invalidate(torrents),
                data: (list) =>
                    Column(children: [for (final t in list) Text(t)]),
              ),
            ),
          ),
        ),
      ),
    );

    /// Unmounts the tree and disposes the container, which cancels the retry
    /// timer Riverpod still has pending, or the test ends on a live timer.
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }

    testWidgets('keeps the last list under a band, tick after tick', (
      tester,
    ) async {
      await pumpList(tester);
      await tester.pump();
      expect(find.text('Ubuntu.ISO'), findsOneWidget);

      down = true;
      for (var tick = 1; tick <= 5; tick++) {
        container.invalidate(torrents);
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));

        final state = container.read(torrents);
        expect(
          state.isLoading && state.hasValue && state.hasError,
          isTrue,
          reason: 'tick $tick: the retry state this group is about',
        );
        expect(find.text('Ubuntu.ISO'), findsOneWidget, reason: 'tick $tick');
        expect(find.byType(FaultBand), findsOneWidget, reason: 'tick $tick');
        expect(find.textContaining('did not answer'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }

      // Back up: the next tick heals it, and the band goes with the fault.
      down = false;
      container.invalidate(torrents);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(torrents).hasError, isFalse);
      expect(find.byType(FaultBand), findsNothing);
      expect(find.text('Debian.ISO'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('a cold failure still loads while the retry runs', (
      tester,
    ) async {
      // Nothing retained, so nothing to keep: the loading state is the honest
      // one while a blip may still heal itself, which is what the default
      // retry is left on for.
      down = true;
      await pumpList(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(torrents).hasError, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(FaultBand), findsNothing);

      await unmount(tester);
    });
  });

  group('a read whose client was closed under it', () {
    // Dio's own refusal of a request on a closed client: the connection's
    // settings changed and its provider closed the client the read held.
    Future<Object> closedClientError() async {
      final dio = Dio()..close();
      try {
        await dio.get<dynamic>('http://nas.home.arpa:7878/api/v3/movie');
      } catch (error) {
        return error;
      }
      fail('a closed client sent the request');
    }

    testWidgets('keeps what it had, under no band', (tester) async {
      final error = await closedClientError();
      expect(isClosedClientFailure(error), isTrue);

      await _pump(tester, _failedOver('tank ONLINE', error: error));

      expect(find.text('tank ONLINE'), findsOneWidget);
      expect(find.byType(FaultBand), findsNothing);
      expect(find.textContaining('did not answer'), findsNothing);
    });

    testWidgets('with nothing retained, loads', (tester) async {
      final error = await closedClientError();

      await _pump(tester, AsyncValue<String>.error(error, StackTrace.empty));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.textContaining('did not answer'), findsNothing);
    });

    testWidgets('AppErrorState loads and asks again, once', (tester) async {
      final error = await closedClientError();
      var asked = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppErrorState(
              error: error,
              serviceName: 'Radarr',
              onRetry: () => asked++,
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('did not answer'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.bySemanticsLabel('Loading Radarr'), findsOneWidget);

      await tester.pump();
      await tester.pump();
      expect(asked, 1);
    });
  });
}

class _Count extends Notifier<int> {
  @override
  int build() => 2;

  void bump() => state++;
}
