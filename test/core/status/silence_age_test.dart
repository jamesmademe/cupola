import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/poll_probe.dart';
import 'package:cupola/core/status/read_age.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/status/silence_age.dart';
import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/core/utils/sample_age.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// A page that prints how long its connection has not answered, and counts
/// how often it was built.
class _Page extends ConsumerWidget {
  const _Page({required this.silent, required this.onBuild, this.instanceId});

  final bool silent;
  final String? instanceId;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onBuild();
    final span = ref.watchSilence(
      context,
      ServiceKey.sabnzbd,
      silent: silent,
      instanceId: instanceId,
    );
    final since = ref.silentSince(ServiceKey.sabnzbd, instanceId: instanceId);
    final spoken = span == null ? null : formatElapsedSpan(span);
    return Text(
      '${span == null ? 'no span' : spoken ?? 'under a minute'}'
      ' | ${since == null ? 'no instant' : since.toIso8601String()}',
    );
  }
}

final _settings = SettingsModel(
  instances: [
    const ServiceInstance(
      id: 'home',
      service: ServiceKey.sabnzbd,
      url: 'http://home.sab.test',
      credential: 'home-key',
    ),
    const ServiceInstance(
      id: 'seedbox',
      service: ServiceKey.sabnzbd,
      url: 'http://seedbox.sab.test',
      credential: 'seedbox-key',
    ),
  ],
);

void main() {
  final silentAt = DateTime(2026, 10, 12, 9);

  late DateTime now;
  late SilenceClock silence;
  late int builds;

  setUp(() {
    now = silentAt.add(const Duration(minutes: 6));
    silence = SilenceClock(now: () => now)
      ..noteSilent(silenceKey(ServiceKey.sabnzbd, 'home'), silentAt);
    builds = 0;
    PollProbe.instance.reset();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool silent = true,
    String lens = 'home',
    String? instanceId,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _settings),
          initialActiveInstancesProvider.overrideWithValue({
            ServiceKey.sabnzbd: lens,
          }),
          readClockProvider.overrideWithValue(ReadClock(now: () => now)),
          silenceClockProvider.overrideWithValue(silence),
        ],
        child: MaterialApp(
          home: _Page(
            silent: silent,
            instanceId: instanceId,
            onBuild: () => builds++,
          ),
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.byType(_Page)));
  }

  /// Unmounts, and lets the disposal a dropped watch schedules run.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  int minuteTicks() => PollProbe.instance.countFor('read_age.minute');

  final instant = silentAt.toIso8601String();

  group('a page drawing a connection that did not answer', () {
    testWidgets('is told how long, from the first silence', (tester) async {
      await pump(tester);

      expect(find.text('6 minutes | $instant'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('is told the span move when a minute passes', (tester) async {
      await pump(tester);

      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('7 minutes | $instant'), findsOneWidget);
      expect(minuteTicks(), 1);

      now = now.add(const Duration(hours: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('1 hour | $instant'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('is not rebuilt between two minutes', (tester) async {
      await pump(tester);
      final before = builds;

      await tester.pump(const Duration(seconds: 59));

      expect(builds, before);

      await unmount(tester);
    });

    testWidgets('is told nothing when no silence was recorded', (tester) async {
      silence = SilenceClock(now: () => now);
      final container = await pump(tester);

      expect(find.text('no span | no instant'), findsOneWidget);
      expect(
        container.exists(minuteNowProvider),
        isFalse,
        reason: 'with no span to print there is nothing to renew',
      );

      await unmount(tester);
    });

    testWidgets('is told the span of the lens, not of another connection', (
      tester,
    ) async {
      await pump(tester, lens: 'seedbox');

      expect(find.text('no span | no instant'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('is told the span of the connection a link named', (
      tester,
    ) async {
      await pump(tester, lens: 'seedbox', instanceId: 'home');

      expect(find.text('6 minutes | $instant'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('is never told a negative span', (tester) async {
      now = silentAt.subtract(const Duration(minutes: 3));
      await pump(tester);

      expect(find.text('under a minute | $instant'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('is told under a minute as no number', (tester) async {
      now = silentAt.add(const Duration(seconds: 20));
      await pump(tester);

      expect(find.text('under a minute | $instant'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('a page that is not drawing silence', () {
    testWidgets('is told no span, and starts no timer', (tester) async {
      final container = await pump(tester, silent: false);

      // The instant is still there to read: a line that says a time of day
      // asks for it, and decides for itself whether it is silence.
      expect(find.text('no span | $instant'), findsOneWidget);
      expect(container.exists(minuteNowProvider), isFalse);
      final before = builds;

      await tester.pump(const Duration(minutes: 5));

      expect(minuteTicks(), 0);
      expect(builds, before);

      await unmount(tester);
    });
  });
}
