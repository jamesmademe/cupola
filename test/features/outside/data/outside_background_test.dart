import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/outside/data/outside_background.dart';
import 'package:cupola/features/outside/data/outside_settings.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';

/// The background run is asked for exactly while it serves someone.
void main() {
  late _Scheduler scheduler;
  setUp(() => scheduler = _Scheduler());

  Future<void> settle(
    Set<OutsideNoticeKind> kinds, {
    bool? widgets,
    bool phone = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        outsideSchedulerProvider.overrideWithValue(phone ? scheduler : null),
        outsideNoticeKindsProvider.overrideWithBuild((ref, notifier) => kinds),
        outsideWidgetsInstalledProvider.overrideWith(
          (ref) => widgets == null
              ? Future<bool>.delayed(const Duration(days: 1), () => false)
              : Future.value(widgets),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(outsideScheduleProvider);
    await Future<void>.delayed(Duration.zero);
    container.read(outsideScheduleProvider);
    await Future<void>.delayed(Duration.zero);
  }

  test('a switch on asks for it', () async {
    await settle({OutsideNoticeKind.needsYou}, widgets: false);
    expect(scheduler.calls.last, 'ask');
  });

  test('a widget on a screen asks for it', () async {
    await settle(const {}, widgets: true);
    expect(scheduler.calls.last, 'ask');
  });

  test('with neither, it stops being asked for', () async {
    await settle(const {}, widgets: false);
    expect(scheduler.calls, ['stop']);
  });

  test('nothing is stopped before the widgets have answered', () async {
    await settle(const {});
    expect(scheduler.calls, isEmpty);
  });

  test('a desktop asks for nothing', () async {
    await settle({OutsideNoticeKind.needsYou}, widgets: true, phone: false);
    expect(scheduler.calls, isEmpty);
  });
}

class _Scheduler implements OutsideScheduler {
  final calls = <String>[];

  @override
  Future<void> ask() async => calls.add('ask');

  @override
  Future<void> stop() async => calls.add('stop');
}
