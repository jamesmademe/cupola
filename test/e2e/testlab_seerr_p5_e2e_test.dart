@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_known_arr.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

import '../test_helpers/settings_scope.dart';

/// P5 against the macOS lab: Cupola holds Seerr and the media server, and the
/// Radarr and Sonarr it reads about are only Seerr's.
///
/// The pass reads Seerr's own settings (`/api/v1/settings/radarr` and
/// `/sonarr`) through the app's `knownServers()`, then searches Discover on
/// the same server. No Radarr or Sonarr connection exists here, so the app
/// has no client to call one with, and the addresses Seerr reports are the
/// Compose names it reaches them by (`radarr:7878`), which nothing outside
/// that network resolves: a direct call to an arr is not a thing this test
/// could make by accident. The offline counterpart is `Profiles.p5`.
void main() {
  late _Lab lab;
  ProviderContainer? container;

  setUpAll(() async {
    lab = _Lab.load();
    await lab.waitForSeerr();
    container = await lab.container();
  });

  tearDownAll(() {
    container?.dispose();
    container = null;
  });

  test('holds Seerr and Jellyfin, and no arr at all', () {
    final settings = container!.read(currentSettingsProvider);

    expect(settings.isServiceConfigured(ServiceKey.seerr), isTrue);
    expect(settings.isServiceConfigured(ServiceKey.jellyfin), isTrue);
    expect(settings.isServiceConfigured(ServiceKey.radarr), isFalse);
    expect(settings.isServiceConfigured(ServiceKey.sonarr), isFalse);
    expect(settings.instancesOf(ServiceKey.radarr), isEmpty);
    expect(settings.instancesOf(ServiceKey.sonarr), isEmpty);

    // No connection, no client: the providers refuse before any request.
    // Riverpod wraps a provider's throw in its own exception; the cause is the
    // typed refusal the placeholders match on.
    Matcher refusesBecauseNotConfigured() => throwsA(
      isA<Object>().having(
        (error) => (error as dynamic).exception,
        'exception',
        isA<ServiceNotConfigured>(),
      ),
    );
    expect(
      () => container!.read(radarrServiceProvider),
      refusesBecauseNotConfigured(),
    );
    expect(
      () => container!.read(sonarrServiceProvider),
      refusesBecauseNotConfigured(),
    );
  });

  test(
    'reads Radarr and Sonarr from Seerr, and knows them as Seerr\'s own',
    () async {
      final known = await container!.read(seerrServiceProvider).knownServers();

      expect(known, isA<SeerrKnownArrsRead>());
      final servers = (known as SeerrKnownArrsRead).servers;
      expect(servers, hasLength(2));

      final radarr = servers.singleWhere(
        (arr) => arr.service == ServiceKey.radarr,
      );
      final sonarr = servers.singleWhere(
        (arr) => arr.service == ServiceKey.sonarr,
      );

      // Seerr reaches them by container name, on the lab's Compose network.
      expect(radarr.address, 'http://radarr:7878');
      expect(sonarr.address, 'http://sonarr:8989');
      expect(radarr.server.isDefault, isTrue);
      expect(sonarr.server.isDefault, isTrue);
      // Seerr holds their keys; they stay secrets.
      expect(radarr.apiKey, isNotEmpty);
      expect(sonarr.apiKey, isNotEmpty);
      expect(radarr.toString(), isNot(contains(radarr.apiKey!)));

      // The address is not where this device would reach an arr even if it
      // tried: nothing resolves it outside the Compose network.
      expect(Uri.parse(radarr.address!).host, 'radarr');
      expect(Uri.parse(sonarr.address!).host, 'sonarr');
    },
  );

  test('a search in Discover finds a title Seerr knows', () async {
    final seerr = container!.read(seerrServiceProvider);

    final answer = await seerr.search('The Dark Knight');

    expect(answer.titles, isNotEmpty);
    final found = answer.titles.where((title) => title.id == _movie);
    expect(found, isNotEmpty, reason: 'TMDB $_movie is in the results');
    expect(found.first.title, contains('Dark Knight'));

    // Seerr's own record of the title: the catalog it answers from, with no
    // arr in the path.
    final movie = await seerr.getMovie(_movie);
    expect(movie['title'], 'The Dark Knight');
    expect(movie['id'], _movie);

    // One answer in the path, Seerr's: Cupola holds no Radarr to ask.
    expect(
      container!.read(currentSettingsProvider).instancesOf(ServiceKey.radarr),
      isEmpty,
    );
  });
}

/// The Dark Knight (2008): a title TMDB knows, so Seerr's catalog carries it.
const _movie = 155;

/// The lab as the bootstrap left it.
class _Lab {
  _Lab._(this._values);

  factory _Lab.load() {
    final named = Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'];
    final path = named == null || named.isEmpty
        ? '.ai/scratch/zz_testlab/state/credentials.env'
        : named;
    final file = File(path);
    if (!file.existsSync()) {
      fail(
        'No lab credentials at $path: run test/e2e/testlab/bootstrap.sh, or '
        'point CUPOLA_TESTLAB_CREDENTIALS_FILE at its credentials file.',
      );
    }
    final values = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      values[line.substring(0, separator)] = line.substring(separator + 1);
    }
    return _Lab._(values);
  }

  final Map<String, String> _values;

  String _value(String name) {
    final value = _values[name];
    if (value == null || value.isEmpty) {
      fail('The lab credentials have no $name: run the bootstrap again.');
    }
    return value;
  }

  static const seerrUrl = 'http://127.0.0.1:5055';
  static const jellyfinUrl = 'http://127.0.0.1:8096';

  /// Cupola's Seerr connection: the key, on the primary id, the lens.
  ServiceInstance seerrConnection() => ServiceInstance(
    id: ServiceInstance.primaryIdFor(ServiceKey.seerr),
    service: ServiceKey.seerr,
    url: seerrUrl,
    credential: _value('CUPOLA_TESTLAB_SEERR_API_KEY'),
  );

  /// The media server beside it, as P5 has it.
  ServiceInstance jellyfinConnection() => ServiceInstance(
    id: ServiceInstance.primaryIdFor(ServiceKey.jellyfin),
    service: ServiceKey.jellyfin,
    url: jellyfinUrl,
    credential: _value('CUPOLA_TESTLAB_JELLYFIN_TOKEN'),
  );

  Future<ProviderContainer> container() async {
    final overrides = await settingsScopeOverrides(
      customize: (settings) => settings
          .copyWithInstance(seerrConnection())
          .copyWithInstance(jellyfinConnection()),
    );
    return ProviderContainer(overrides: overrides);
  }

  Future<void> waitForSeerr() async {
    for (var attempt = 0; attempt < 90; attempt++) {
      try {
        final status = await _rawStatus();
        if (status == 200) return;
      } on IOException {
        // Not up yet.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    fail('The lab Seerr did not come up at $seerrUrl');
  }

  Future<int> _rawStatus() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$seerrUrl/api/v1/status'));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }
}
