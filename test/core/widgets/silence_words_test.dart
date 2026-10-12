/// The widgets that say a connection did not answer say since when, from the
/// silence the probe recorded, and say nothing of it where nothing recorded
/// one.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/poll_probe.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

// ignore: invalid_use_of_internal_member
AsyncValue<T> _failedOver<T>(T retained, {Object? error}) {
  return AsyncValue<T>.error(
    error ?? const SocketException('Connection refused'),
    StackTrace.empty,
    // ignore: invalid_use_of_internal_member
  ).copyWithPrevious(AsyncValue<T>.data(retained));
}

final _settings = SettingsModel(
  instances: [
    const ServiceInstance(
      id: 'main',
      service: ServiceKey.radarr,
      url: 'http://radarr.test',
      credential: 'key',
    ),
    const ServiceInstance(
      id: 'uhd',
      service: ServiceKey.radarr,
      url: 'http://radarr-uhd.test',
      credential: 'key',
    ),
  ],
);

void main() {
  final silentAt = DateTime(2026, 10, 12, 9);
  late DateTime now;
  late SilenceClock silence;

  setUp(() {
    now = silentAt.add(const Duration(minutes: 6));
    silence = SilenceClock(now: () => now);
    PollProbe.instance.reset();
  });

  Future<void> pump(WidgetTester tester, Widget child, {String lens = 'main'}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _settings),
          initialActiveInstancesProvider.overrideWithValue({
            ServiceKey.radarr: lens,
          }),
          readClockProvider.overrideWithValue(ReadClock(now: () => now)),
          silenceClockProvider.overrideWithValue(silence),
        ],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  AsyncValueWidget<String> section({
    required AsyncValue<String> value,
    String? instanceId,
  }) => AsyncValueWidget<String>.section(
    value: value,
    service: ServiceKey.radarr,
    consequence: 'its list is missing',
    instanceId: instanceId,
    onRetry: () {},
    data: (data) => Text(data),
  );

  group('the band over a read that did not come back', () {
    testWidgets('a section says since when its connection did not answer', (
      tester,
    ) async {
      silence.noteSilent(silenceKey(ServiceKey.radarr, 'main'), silentAt);

      await pump(tester, section(value: _failedOver('list')));

      expect(find.text('list'), findsOneWidget);
      expect(
        find.textContaining('Radarr has not answered for 6 minutes'),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('a section says nothing of how long when none was recorded', (
      tester,
    ) async {
      await pump(tester, section(value: _failedOver('list')));

      expect(find.textContaining('Radarr did not answer'), findsOneWidget);
      expect(find.textContaining('has not answered for'), findsNothing);

      await unmount(tester);
    });

    testWidgets('a section reads the connection it names, not the lens', (
      tester,
    ) async {
      silence.noteSilent(silenceKey(ServiceKey.radarr, 'main'), silentAt);
      silence.noteSilent(
        silenceKey(ServiceKey.radarr, 'uhd'),
        silentAt.add(const Duration(minutes: 2)),
      );

      await pump(
        tester,
        section(value: _failedOver('list'), instanceId: 'uhd'),
      );

      expect(find.textContaining('has not answered for 4 minutes'), findsOne);

      await unmount(tester);
    });

    testWidgets('a section on the other lens reads the other silence', (
      tester,
    ) async {
      silence.noteSilent(silenceKey(ServiceKey.radarr, 'main'), silentAt);

      await pump(tester, section(value: _failedOver('list')), lens: 'uhd');

      expect(find.textContaining('has not answered for'), findsNothing);
      expect(find.textContaining('Radarr did not answer'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('a page that names its service says it too', (tester) async {
      silence.noteSilent(silenceKey(ServiceKey.radarr, 'main'), silentAt);

      await pump(
        tester,
        AsyncValueWidget<String>(
          value: _failedOver('queue'),
          serviceName: 'Radarr',
          silentService: ServiceKey.radarr,
          onRetry: () {},
          data: (data) => Text(data),
        ),
      );

      expect(
        find.textContaining('Radarr has not answered for 6 minutes'),
        findsOne,
      );

      await unmount(tester);
    });

    testWidgets('a page that names no service never claims a span', (
      tester,
    ) async {
      silence.noteSilent(silenceKey(ServiceKey.radarr, 'main'), silentAt);

      await pump(
        tester,
        AsyncValueWidget<String>(
          value: _failedOver('queue'),
          serviceName: 'Radarr',
          onRetry: () {},
          data: (data) => Text(data),
        ),
      );

      expect(find.textContaining('Radarr did not answer'), findsOneWidget);
      expect(find.textContaining('has not answered for'), findsNothing);

      await unmount(tester);
    });

    testWidgets('an answer that refused is no silence, whatever was recorded', (
      tester,
    ) async {
      silence.noteSilent(silenceKey(ServiceKey.radarr, 'main'), silentAt);

      await pump(
        tester,
        section(
          value: _failedOver(
            'list',
            error: const ClassifiedFailure(ServiceFailureReason.unauthorized),
          ),
        ),
      );

      expect(find.textContaining('has not answered for'), findsNothing);
      expect(find.textContaining('refused the key'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('draws without a provider scope when it can read no span', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncValueWidget<String>(
              value: _failedOver('queue'),
              serviceName: 'Radarr',
              silentService: ServiceKey.radarr,
              onRetry: () {},
              data: (data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.text('queue'), findsOneWidget);
      expect(find.textContaining('Radarr did not answer'), findsOneWidget);
    });
  });

  group('the leaf over a read with nothing to keep', () {
    Widget leaf({Object? error}) => ServiceOfflineState.failure(
      service: ServiceKey.radarr,
      error: error ?? const SocketException('Connection refused'),
      onRetry: () {},
    );

    testWidgets('says since when the lens connection did not answer', (
      tester,
    ) async {
      silence.noteSilent(silenceKey(ServiceKey.radarr, 'main'), silentAt);

      await pump(tester, leaf());

      expect(
        find.textContaining('It has not answered for 6 minutes.'),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('says nothing of how long when none was recorded', (
      tester,
    ) async {
      await pump(tester, leaf());

      expect(find.text('Radarr did not answer'), findsOneWidget);
      expect(find.textContaining('It has not answered for'), findsNothing);

      await unmount(tester);
    });

    testWidgets('reads the lens connection, not another', (tester) async {
      silence.noteSilent(silenceKey(ServiceKey.radarr, 'main'), silentAt);

      await pump(tester, leaf(), lens: 'uhd');

      expect(find.textContaining('It has not answered for'), findsNothing);

      await unmount(tester);
    });

    testWidgets('keeps the time it was handed over the clock', (tester) async {
      silence.noteSilent(silenceKey(ServiceKey.radarr, 'main'), silentAt);

      await pump(
        tester,
        ServiceOfflineState.failure(
          service: ServiceKey.radarr,
          error: const SocketException('Connection refused'),
          since: const Duration(hours: 2),
          onRetry: () {},
        ),
      );

      expect(
        find.textContaining('It has not answered for 2 hours.'),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('an answer that refused carries no span', (tester) async {
      silence.noteSilent(silenceKey(ServiceKey.radarr, 'main'), silentAt);

      await pump(
        tester,
        leaf(error: const ClassifiedFailure(ServiceFailureReason.unauthorized)),
      );

      expect(find.textContaining('has not answered for'), findsNothing);

      await unmount(tester);
    });

    testWidgets('from a failed probe says what the page handed it', (
      tester,
    ) async {
      await pump(
        tester,
        ServiceOfflineState.fromSummary(
          summary: const ServiceSummary(
            service: ServiceKey.sabnzbd,
            status: ServiceSummaryStatus.offline,
            host: 'nas.local',
            version: null,
          ),
          since: const Duration(minutes: 6),
          onRetry: () {},
        ),
      );

      expect(
        find.textContaining('It has not answered for 6 minutes.'),
        findsOneWidget,
      );

      await unmount(tester);
    });
  });
}
