import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/domain/set_up_next.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
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
    expect(suggestions.first.line, 'Play, Continue watching and Now playing');
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

  test('what another connection knows comes first, and stands for its '
      'service', () {
    const seerr = CandidateSource(
      service: ServiceKey.seerr,
      connectionId: 'seerr',
      url: 'http://nas.lan:5055',
    );
    const prowlarr = CandidateSource(
      service: ServiceKey.prowlarr,
      connectionId: 'prowlarr',
      url: 'http://nas.lan:9696',
    );
    const found = [
      ConnectionCandidate(
        service: ServiceKey.radarr,
        name: 'Radarr 4K',
        reportedUrl: 'http://nas.lan:7879',
        source: seerr,
        apiKey: 'found-key',
      ),
      ConnectionCandidate(
        service: ServiceKey.sonarr,
        name: 'Sonarr',
        reportedUrl: 'http://nas.lan:8989',
        source: prowlarr,
      ),
    ];

    final suggestions = setUpNextOf({ServiceKey.seerr}.contains, found: found);

    expect(
      [for (final s in suggestions) s.title],
      [
        'Add Radarr 4K',
        'Add Sonarr',
        'Set up Jellyfin',
        'Set up a download client',
        'Set up Bazarr',
      ],
    );
    expect(suggestions[0].line, 'Seerr knows it\u00A0· key found');
    expect(suggestions[1].line, 'Prowlarr knows it\u00A0· paste its key');
    expect(suggestions[0].found, found[0]);
    expect(suggestions[2].found, isNull);
  });
}
