/// Since when the services Needs you leads with have not answered: the latest
/// silence among their connections, or nothing when any is not on record.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/features/home/presentation/widgets/needs_you_banner.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

void main() {
  const radarr = ServiceInstance(
    id: 'radarr',
    service: ServiceKey.radarr,
    url: 'http://nas:7878',
    credential: 'k',
  );
  const radarr4k = ServiceInstance(
    id: 'radarr-4k',
    service: ServiceKey.radarr,
    url: 'http://nas:7879',
    credential: 'k',
  );
  const sonarr = ServiceInstance(
    id: 'sonarr',
    service: ServiceKey.sonarr,
    url: 'http://nas:8989',
    credential: 'k',
  );
  final settings = const SettingsModel().copyWith(
    instances: const [radarr, radarr4k, sonarr],
  );

  test('the latest silence of every connection of every service', () {
    final clock = SilenceClock()
      ..noteSilent(
        silenceKey(ServiceKey.radarr, 'radarr'),
        DateTime(2026, 1, 1, 20, 10),
      )
      ..noteSilent(
        silenceKey(ServiceKey.radarr, 'radarr-4k'),
        DateTime(2026, 1, 1, 20, 30),
      )
      ..noteSilent(
        silenceKey(ServiceKey.sonarr, 'sonarr'),
        DateTime(2026, 1, 1, 20, 20),
      );
    expect(
      silentSinceOf(
        const [ServiceKey.radarr, ServiceKey.sonarr],
        clock,
        settings,
      ),
      DateTime(2026, 1, 1, 20, 30),
    );
  });

  test('a connection with no silence on record says no time at all', () {
    final clock = SilenceClock()
      ..noteSilent(
        silenceKey(ServiceKey.radarr, 'radarr'),
        DateTime(2026, 1, 1, 20, 10),
      );
    expect(silentSinceOf(const [ServiceKey.radarr], clock, settings), isNull);
  });
}
