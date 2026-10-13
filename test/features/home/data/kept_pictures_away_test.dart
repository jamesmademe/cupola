/// A picture a last drawing keeps is bound to its connection and its path,
/// never to the address it was drawn from: kept at home, it draws away from
/// home at the address in use, across that address's gateway.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/calendar_event_codec.dart';
import 'package:cupola/features/home/data/last_known/coming_up_last_known.dart';
import 'package:cupola/features/home/data/last_known/featured_last_known.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

const _token = CloudflareServiceToken(
  clientId: 'id.access',
  clientSecret: 'sentinel-secret',
);

/// At home on the LAN, away under a path of a tunnel.
const _radarr = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  url: 'http://192.168.1.20:7878',
  credential: 'radarr-key',
  away: ConnectionAddress(
    url: 'https://media.example.com/radarr',
    access: _token,
  ),
);

const _settings = SettingsModel(instances: [_radarr]);

const _poster = '/MediaCover/12/poster.jpg?lastWrite=1';

ImageSource _drawnAt(String base) => ImageUtils.extractPosterUrl(
  const [
    {'coverType': 'poster', 'url': _poster},
  ],
  baseUrl: base,
  apiKey: 'radarr-key',
);

StoredImage? _kept(ImageSource source) => storedImageKeeper(_settings)(
  source,
  service: ServiceKey.radarr,
  connectionId: 'radarr',
);

Future<ProviderContainer> _container() async {
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      currentSettingsProvider.overrideWith((ref) => _settings),
      initialActiveInstancesProvider.overrideWithValue(const {}),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// [image] drawn as the Home draws a kept picture, against [container]'s
/// connections and routes.
ImageSource _drawn(ProviderContainer container, StoredImage image) => container
    .read(Provider((ref) => resolveStoredImage(ref, _settings, image)));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a picture is kept by its connection and its path', () {
    test('drawn at home or away, it keeps the same thing, and no address', () {
      final atHome = _kept(_drawnAt(_radarr.url));
      final away = _kept(_drawnAt(_radarr.away!.url));

      const expected = StoredArrImage(
        service: ServiceKey.radarr,
        connectionId: 'radarr',
        path: _poster,
      );
      expect(atHome, expected);
      expect(away, expected);
      final json = jsonEncode(atHome!.toJson());
      expect(json, isNot(contains('192.168.1.20')));
      expect(json, isNot(contains('radarr-key')));
    });

    test(
      'a picture at an address that is not its connection\'s is not kept',
      () {
        expect(_kept(_drawnAt('https://elsewhere.example.net')), isNull);
      },
    );

    test('a picture kept by address, before the address away, reads as '
        'nothing', () {
      final old = {
        'kind': 'arr',
        'service': 'radarr',
        'connection': 'radarr',
        'url': 'http://192.168.1.20:7878$_poster',
      };
      expect(StoredImage.fromJson(old), isNull);
    });

    test('the drawings that keep an arr\'s picture moved to a new schema, so '
        'an entry kept by address is dropped', () {
      expect(comingUpLastKnown.schema, greaterThan(1));
      expect(featuredLastKnown.schema, greaterThan(1));

      final store = LastKnownStore.memory()
        ..write(
          'home.operator.comingUp',
          validity: 'v',
          schema: 1,
          data: const {'events': <Object>[]},
          takenAt: DateTime(2026, 10, 13, 9),
        );
      expect(
        store.read(
          'home.operator.comingUp',
          validity: 'v',
          schema: comingUpLastKnown.schema,
        ),
        isNull,
      );
    });
  });

  group('a kept picture draws where the connection is reached now', () {
    const kept = StoredArrImage(
      service: ServiceKey.radarr,
      connectionId: 'radarr',
      path: _poster,
    );

    test(
      'at home: the address at home, the key, nothing for a gateway',
      () async {
        final container = await _container();

        final drawn = _drawn(container, kept);

        expect(drawn.url, 'http://192.168.1.20:7878$_poster');
        expect(drawn.headers, {'X-Api-Key': 'radarr-key'});
      },
    );

    test('away: the address away, its gateway\'s access and the key', () async {
      final container = await _container();
      await container
          .read(connectionRoutesProvider.notifier)
          .set('radarr', ConnectionRoute.away);

      final drawn = _drawn(container, kept);

      expect(drawn.url, 'https://media.example.com/radarr$_poster');
      expect(drawn.headers, {..._token.headers(), 'X-Api-Key': 'radarr-key'});
    });

    test('an event drawn at home is drawn away from home whole', () async {
      final container = await _container();
      final event = CalendarEvent(
        identity: 'movie:12:digitalRelease',
        kind: CalendarKind.movie,
        day: DateTime(2026, 10, 14),
        title: 'Sprite Fright',
        poster: _drawnAt(_radarr.url),
        sources: const ['Radarr'],
        state: const CalendarState.notYet(),
        target: const CalendarMediaTarget(
          MediaKey.movie(12),
          connectionId: 'radarr',
        ),
      );
      final json = jsonDecode(
        jsonEncode(calendarEventToJson(event, storedImageKeeper(_settings))),
      );
      await container
          .read(connectionRoutesProvider.notifier)
          .set('radarr', ConnectionRoute.away);

      final back = calendarEventFromJson(
        json,
        (image) => _drawn(container, image),
      );

      expect(back?.poster?.url, 'https://media.example.com/radarr$_poster');
      expect(back?.poster?.headers?['CF-Access-Client-Id'], 'id.access');
    });

    test('a connection since removed draws nothing', () async {
      final container = await _container();
      const gone = StoredArrImage(
        service: ServiceKey.radarr,
        connectionId: 'radarr-gone',
        path: _poster,
      );

      expect(_drawn(container, gone), noImage);
    });
  });
}
