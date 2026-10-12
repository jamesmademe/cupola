import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// A SABnzbd that answers the queue, or refuses.
class _Sabnzbd implements SabnzbdClient {
  bool down = false;

  @override
  Future<SabnzbdQueue> getQueue({int limit = 50}) async {
    if (down) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api?mode=queue'),
        message: 'connection refused',
      );
    }
    return const SabnzbdQueue(
      paused: false,
      status: 'Idle',
      kbPerSec: 0,
      mbLeft: 0,
      mb: 0,
      timeLeft: '0:00:00',
      slots: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

String _key(String connection) => queueReadKey(ServiceKey.sabnzbd, connection);

void main() {
  late _Sabnzbd sabnzbd;
  late DateTime now;
  late ReadClock clock;

  setUp(() {
    sabnzbd = _Sabnzbd();
    now = DateTime(2026, 10, 12, 9);
    clock = ReadClock(now: () => now);
  });

  ProviderContainer containerOn(String lens) {
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => _settings),
        initialActiveInstancesProvider.overrideWithValue({
          ServiceKey.sabnzbd: lens,
        }),
        readClockProvider.overrideWithValue(clock),
        sabnzbdClientProvider.overrideWithValue(sabnzbd),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the queue is noted as read, for the connection it came from', () async {
    final container = containerOn('seedbox');

    await container.read(sabnzbdQueueProvider.future);

    expect(clock.at(_key('seedbox')), now);
    expect(clock.at(_key('home')), isNull);
  });

  test(
    'a queue that failed notes nothing, and a later failure keeps the read',
    () async {
      final container = containerOn('home');
      sabnzbd.down = true;
      await expectLater(
        container.read(sabnzbdQueueProvider.future),
        throwsA(isA<DioException>()),
      );
      expect(clock.at(_key('home')), isNull);

      sabnzbd.down = false;
      container.invalidate(sabnzbdQueueProvider);
      await container.read(sabnzbdQueueProvider.future);
      final readAt = now;

      now = now.add(const Duration(minutes: 6));
      sabnzbd.down = true;
      container.invalidate(sabnzbdQueueProvider);
      await expectLater(
        container.read(sabnzbdQueueProvider.future),
        throwsA(isA<DioException>()),
      );
      expect(clock.at(_key('home')), readAt);
    },
  );
}
