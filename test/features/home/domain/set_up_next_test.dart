import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/domain/set_up_next.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Set up next names what the stack lacks, once, in the order of what it
/// adds.
void main() {
  List<String> titles(Set<ServiceKey> setUp) => [
    for (final suggestion in setUpNextOf(setUp.contains)) suggestion.title,
  ];

  test('a first day with three services: what each missing one adds', () {
    final suggestions = setUpNextOf(
      {ServiceKey.radarr, ServiceKey.sonarr, ServiceKey.seerr}.contains,
    );
    expect(
      [for (final s in suggestions) s.title],
      ['Set up Jellyfin', 'Set up a download client', 'Set up Bazarr'],
    );
    expect(suggestions.first.service, ServiceKey.jellyfin);
    expect(suggestions.first.line, 'Play on every title, and Now playing');
    // A kind of service, not one: it leads to the whole list.
    expect(suggestions[1].service, isNull);
  });

  test('no Seerr comes first: it adds the most', () {
    expect(
      titles({ServiceKey.radarr, ServiceKey.qbittorrent}).first,
      'Set up Seerr',
    );
  });

  test('Plex stands for Jellyfin, any client for the four', () {
    final names = titles({
      ServiceKey.seerr,
      ServiceKey.plex,
      ServiceKey.sabnzbd,
      ServiceKey.radarr,
      ServiceKey.sonarr,
    });
    expect(names, ['Set up Bazarr']);
  });

  test('nothing it knows of missing: no module', () {
    expect(
      setUpNextOf(
        {
          ServiceKey.seerr,
          ServiceKey.jellyfin,
          ServiceKey.transmission,
          ServiceKey.radarr,
          ServiceKey.sonarr,
          ServiceKey.bazarr,
        }.contains,
      ),
      isEmpty,
    );
  });

  test('the module names three, then All services', () {
    expect(setUpNextLimit, 3);
    expect(titles(const {}).length, greaterThan(setUpNextLimit));
  });
}
