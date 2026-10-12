import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

/// A daemon that answers `torrent-get` with an empty list, or refuses.
class _Daemon implements TransmissionClient {
  bool down = false;

  @override
  Future<List<TransmissionTorrent>> torrents({List<String>? ids}) async {
    if (down) throw Exception('connection refused');
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _settings = SettingsModel(
  instances: [
    const ServiceInstance(
      id: 'home',
      service: ServiceKey.transmission,
      url: 'http://home.transmission.test',
    ),
    const ServiceInstance(
      id: 'seedbox',
      service: ServiceKey.transmission,
      url: 'http://seedbox.transmission.test',
    ),
  ],
);

String _key(String connection) =>
    queueReadKey(ServiceKey.transmission, connection);

void main() {
  late _Daemon daemon;
  late DateTime now;
  late ReadClock clock;

  setUp(() {
    daemon = _Daemon();
    now = DateTime(2026, 10, 12, 9);
    clock = ReadClock(now: () => now);
  });

  ProviderContainer containerOn(String lens) {
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => _settings),
        initialActiveInstancesProvider.overrideWithValue({
          ServiceKey.transmission: lens,
        }),
        readClockProvider.overrideWithValue(clock),
        transmissionClientProvider.overrideWithValue(daemon),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'the torrent list is noted as read, for the connection it came from',
    () async {
      final container = containerOn('seedbox');

      await container.read(transmissionTorrentsProvider.future);

      expect(clock.at(_key('seedbox')), now);
      expect(clock.at(_key('home')), isNull);
    },
  );

  test(
    'a list that failed notes nothing, and a later failure keeps the read',
    () async {
      final container = containerOn('home');
      daemon.down = true;
      await expectLater(
        container.read(transmissionTorrentsProvider.future),
        throwsException,
      );
      expect(clock.at(_key('home')), isNull);

      daemon.down = false;
      container.invalidate(transmissionTorrentsProvider);
      await container.read(transmissionTorrentsProvider.future);
      final readAt = now;

      now = now.add(const Duration(minutes: 6));
      daemon.down = true;
      container.invalidate(transmissionTorrentsProvider);
      await expectLater(
        container.read(transmissionTorrentsProvider.future),
        throwsException,
      );
      expect(clock.at(_key('home')), readAt);
    },
  );
}
