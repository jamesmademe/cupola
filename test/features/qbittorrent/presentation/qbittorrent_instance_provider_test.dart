import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

void main() {
  test('routes a second connection and reuses the lens client', () {
    final settings = SettingsModel(
      instances: [
        const ServiceInstance(
          id: 'qbittorrent',
          service: ServiceKey.qbittorrent,
          url: 'https://home.test',
          username: 'home',
          credential: 'home-password',
        ),
        const ServiceInstance(
          id: 'qb-seedbox',
          service: ServiceKey.qbittorrent,
          url: 'https://seedbox.test',
          username: 'seedbox',
          credential: 'seedbox-password',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        initialActiveInstancesProvider.overrideWithValue({
          ServiceKey.qbittorrent: 'qb-seedbox',
        }),
      ],
    );
    addTearDown(container.dispose);

    final lens = container.read(qbittorrentServiceProvider);
    expect(lens.baseUrl, 'https://seedbox.test');
    expect(container.read(qbittorrentServiceForProvider('')), same(lens));
    expect(
      container.read(qbittorrentServiceForProvider('qb-seedbox')),
      same(lens),
    );

    final second = container.read(qbittorrentServiceForProvider('qbittorrent'));
    expect(second.baseUrl, 'https://home.test');
    expect(
      container.read(qbittorrentServiceForProvider('qbittorrent')),
      same(second),
    );
  });
}
