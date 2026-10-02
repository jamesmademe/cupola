import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_known_arr.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One server of `GET /api/v1/settings/radarr` as Seerr sends it: its
/// `RadarrSettings` (`server/lib/settings/index.ts`), returned whole by
/// `server/routes/settings/radarr.ts`, the key in the clear.
Map<String, dynamic> _radarr({
  Object? hostname = 'radarr-4k',
  Object? port = 7878,
  Object? useSsl = false,
  Object? baseUrl,
  Object? apiKey = _sentinel,
  Object? externalUrl,
}) => {
  'id': 1,
  'name': 'Radarr 4K',
  'hostname': hostname,
  'port': port,
  'apiKey': apiKey,
  'useSsl': useSsl,
  'baseUrl': ?baseUrl,
  'activeProfileId': 4,
  'activeProfileName': 'Ultra-HD',
  'activeDirectory': '/movies-4k',
  'tags': <Object?>[],
  'is4k': true,
  'isDefault': true,
  'externalUrl': ?externalUrl,
  'syncEnabled': true,
  'preventSearch': false,
  'tagRequests': false,
  'overrideRule': <Object?>[],
  'minimumAvailability': 'released',
};

/// Stands for a key wherever one would leak: nothing printed may contain it.
const _sentinel = 'sentinel-key-0f3a9c';

SeerrKnownArr _parse(Map<String, dynamic> json) =>
    SeerrKnownArr.fromSettingsJson(json, service: ServiceKey.radarr);

void main() {
  group('SeerrKnownArr.fromSettingsJson', () {
    test('reads the server, its flags and the key Seerr holds', () {
      final known = _parse(_radarr());

      expect(known.service, ServiceKey.radarr);
      expect(known.server.id, 1);
      expect(known.name, 'Radarr 4K');
      expect(known.is4k, isTrue);
      expect(known.isDefault, isTrue);
      expect(known.apiKey, _sentinel);
      expect(known.server.activeProfileId, 4);
    });

    test('builds the address the way Seerr builds it', () {
      expect(_parse(_radarr()).address, 'http://radarr-4k:7878');
      expect(
        _parse(
          _radarr(hostname: 'nas.home.arpa', port: 7879, useSsl: true),
        ).address,
        'https://nas.home.arpa:7879',
      );
      expect(
        _parse(_radarr(hostname: 'nas.home.arpa', baseUrl: '/radarr')).address,
        'http://nas.home.arpa:7878/radarr',
      );
    });

    test('tolerates what a hand-edited settings file carries', () {
      expect(
        _parse(
          _radarr(hostname: ' http://radarr/ ', baseUrl: 'radarr/'),
        ).address,
        'http://radarr:7878/radarr',
      );
      expect(_parse(_radarr(hostname: '::1')).address, 'http://[::1]:7878');
      expect(_parse(_radarr(port: '7878')).address, 'http://radarr-4k:7878');
    });

    test('says no address when the settings do not say where', () {
      expect(_parse(_radarr(hostname: '')).address, isNull);
      expect(_parse(_radarr(hostname: null)).address, isNull);
      expect(_parse(_radarr(port: null)).address, isNull);
      expect(_parse(_radarr(port: 0)).address, isNull);
    });

    test('an empty key or browser address is none', () {
      final known = _parse(_radarr(apiKey: '  ', externalUrl: ''));
      expect(known.apiKey, isNull);
      expect(known.externalUrl, isNull);

      expect(
        _parse(_radarr(externalUrl: 'https://radarr.example.com')).externalUrl,
        'https://radarr.example.com',
      );
    });
  });

  group('the key is never printed', () {
    test('toString names the server and says only that a key came', () {
      final known = _parse(_radarr());

      expect(known.toString(), isNot(contains(_sentinel)));
      expect(known.toString(), contains('key: given'));
      expect(known.toString(), contains('http://radarr-4k:7878'));
      expect(_parse(_radarr(apiKey: null)).toString(), contains('key: none'));
    });

    test('nor does the answer that holds it', () {
      final read = SeerrKnownArrsRead([_parse(_radarr())]);

      expect(read.toString(), isNot(contains(_sentinel)));
      expect(read.servers.toString(), isNot(contains(_sentinel)));
    });
  });
}
