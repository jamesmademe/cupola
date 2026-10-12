import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// An NZBGet that answers `listgroups` with an empty queue, or refuses.
class _Nzbget implements NzbgetClient {
  bool down = false;

  @override
  Future<List<NzbgetGroup>> listGroups() async {
    if (down) {
      throw DioException(
        requestOptions: RequestOptions(path: '/jsonrpc/listgroups'),
        message: 'connection refused',
      );
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _settings = SettingsModel(
  instances: [
    const ServiceInstance(
      id: 'home',
      service: ServiceKey.nzbget,
      url: 'http://home.nzbget.test',
    ),
    const ServiceInstance(
      id: 'seedbox',
      service: ServiceKey.nzbget,
      url: 'http://seedbox.nzbget.test',
    ),
  ],
);

String _key(String connection) => queueReadKey(ServiceKey.nzbget, connection);

void main() {
  late _Nzbget nzbget;
  late DateTime now;
  late ReadClock clock;

  setUp(() {
    nzbget = _Nzbget();
    now = DateTime(2026, 10, 12, 9);
    clock = ReadClock(now: () => now);
  });

  ProviderContainer containerOn(String lens) {
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => _settings),
        initialActiveInstancesProvider.overrideWithValue({
          ServiceKey.nzbget: lens,
        }),
        readClockProvider.overrideWithValue(clock),
        nzbgetClientProvider.overrideWithValue(nzbget),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the queue is noted as read, for the connection it came from', () async {
    final container = containerOn('seedbox');

    await container.read(nzbgetQueueProvider.future);

    expect(clock.at(_key('seedbox')), now);
    expect(clock.at(_key('home')), isNull);
  });

  test(
    'a queue that failed notes nothing, and a later failure keeps the read',
    () async {
      final container = containerOn('home');
      nzbget.down = true;
      await expectLater(
        container.read(nzbgetQueueProvider.future),
        throwsA(isA<DioException>()),
      );
      expect(clock.at(_key('home')), isNull);

      nzbget.down = false;
      container.invalidate(nzbgetQueueProvider);
      await container.read(nzbgetQueueProvider.future);
      final readAt = now;

      now = now.add(const Duration(minutes: 6));
      nzbget.down = true;
      container.invalidate(nzbgetQueueProvider);
      await expectLater(
        container.read(nzbgetQueueProvider.future),
        throwsA(isA<DioException>()),
      );
      expect(clock.at(_key('home')), readAt);
    },
  );
}
