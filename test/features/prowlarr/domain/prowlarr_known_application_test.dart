import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/prowlarr/domain/prowlarr_known_application.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One application of `GET /api/v1/applications` as Prowlarr sends it: the
/// implementation's settings as fields, the key masked by
/// `ClientSchema/SchemaBuilder.cs`.
Map<String, dynamic> _app({
  String implementation = 'Radarr',
  String name = 'Radarr 4K',
  Object? baseUrl = 'http://radarr-4k:7878',
  Object? prowlarrUrl = 'http://prowlarr:9696',
}) => {
  'id': 2,
  'name': name,
  'syncLevel': 'fullSync',
  'fields': [
    {'order': 0, 'name': 'prowlarrUrl', 'value': prowlarrUrl},
    {'order': 1, 'name': 'baseUrl', 'value': baseUrl},
    {'order': 2, 'name': 'apiKey', 'value': '********', 'privacy': 'apiKey'},
    {
      'order': 5,
      'name': 'syncCategories',
      'value': [2000, 2010],
    },
  ],
  'implementationName': implementation,
  'implementation': implementation,
  'configContract': '${implementation}Settings',
  'tags': <Object?>[],
};

void main() {
  test('reads the name, the implementation and both addresses', () {
    final app = ProwlarrKnownApplication.fromJson(_app());

    expect(app.id, 2);
    expect(app.name, 'Radarr 4K');
    expect(app.implementation, 'Radarr');
    expect(app.service, ServiceKey.radarr);
    expect(app.baseUrl, 'http://radarr-4k:7878');
    expect(app.prowlarrUrl, 'http://prowlarr:9696');
  });

  test('carries no key at all, not even the mask', () {
    final app = ProwlarrKnownApplication.fromJson(_app());

    expect(app.toString(), isNot(contains('********')));
    expect(app.toString(), contains('http://radarr-4k:7878'));
  });

  test('names the Cupola service of each implementation it knows', () {
    ServiceKey? serviceOf(String implementation) =>
        ProwlarrKnownApplication.fromJson(
          _app(implementation: implementation),
        ).service;

    expect(serviceOf('Sonarr'), ServiceKey.sonarr);
    expect(serviceOf('Lidarr'), ServiceKey.lidarr);
    expect(serviceOf('Readarr'), ServiceKey.readarr);
    expect(serviceOf('Whisparr'), isNull);
    expect(serviceOf('Mylar'), isNull);
    expect(serviceOf('LazyLibrarian'), isNull);
  });

  test('an empty address is none', () {
    final app = ProwlarrKnownApplication.fromJson(
      _app(baseUrl: '', prowlarrUrl: null),
    );

    expect(app.baseUrl, isNull);
    expect(app.prowlarrUrl, isNull);
  });

  test('a credential written into an address is left out', () {
    final app = ProwlarrKnownApplication.fromJson(
      _app(baseUrl: 'http://admin:sentinel-0f3a9c@radarr:7878/radarr'),
    );

    expect(app.baseUrl, 'http://radarr:7878/radarr');
    expect(app.toString(), isNot(contains('sentinel-0f3a9c')));
  });
}
