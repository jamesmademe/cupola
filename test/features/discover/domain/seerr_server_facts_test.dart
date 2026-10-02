import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';

import '../../../test_helpers/fixtures.dart';

/// `GET /api/v1/settings/public` answers `fullPublicSettings`, whose shape
/// changed with every family. The fixtures in `test/fixtures/seerr/` are that
/// getter of each tag, field for field and in its order:
///
///  * Overseerr v1.35.0, `server/lib/settings.ts:493-516` (`sct/overseerr`);
///  * Jellyseerr v1.9.2, `server/lib/settings.ts:533-562`;
///  * Jellyseerr v2.7.3, `server/lib/settings/index.ts:608-641`;
///  * Seerr v3.5.0, `server/lib/settings/index.ts:713-748`
///    (`seerr-team/seerr` for the last three).
///
/// The values are each tag's `Settings` defaults on a server that finished
/// setup: `initialized` true and, past Overseerr, a Jellyfin media server.
/// `vapidPublic` and `plexClientIdentifier` are placeholders. The Seerr one
/// also has a default 4K Radarr and email turned on.
///
/// The schema `PublicSettings` in `seerr-api.yml` lists two fields only, so
/// the getter is the source. `jellyfinServerName` is declared on the
/// interface of three tags and set by none of the getters: no server sends it.
final _fixtures = <String, (String, String, List<String>)>{
  'Overseerr 1.35.0': (
    'seerr/public_settings_overseerr_1.35.0.json',
    '1.35.0',
    [
      'initialized',
      'applicationTitle',
      'applicationUrl',
      'hideAvailable',
      'localLogin',
      'movie4kEnabled',
      'series4kEnabled',
      'region',
      'originalLanguage',
      'partialRequestsEnabled',
      'cacheImages',
      'vapidPublic',
      'enablePushRegistration',
      'locale',
      'emailEnabled',
      'newPlexLogin',
    ],
  ),
  'Jellyseerr 1.9.2': (
    'seerr/public_settings_jellyseerr_1.9.2.json',
    '1.9.2',
    [
      'initialized',
      'applicationTitle',
      'applicationUrl',
      'hideAvailable',
      'localLogin',
      'jellyfinForgotPasswordUrl',
      'movie4kEnabled',
      'series4kEnabled',
      'region',
      'originalLanguage',
      'mediaServerType',
      'jellyfinHost',
      'jellyfinExternalHost',
      'partialRequestsEnabled',
      'cacheImages',
      'vapidPublic',
      'enablePushRegistration',
      'locale',
      'emailEnabled',
      'userEmailRequired',
      'newPlexLogin',
    ],
  ),
  'Jellyseerr 2.7.3': (
    'seerr/public_settings_jellyseerr_2.7.3.json',
    '2.7.3',
    [
      'initialized',
      'applicationTitle',
      'applicationUrl',
      'hideAvailable',
      'hideBlacklisted',
      'localLogin',
      'mediaServerLogin',
      'jellyfinExternalHost',
      'jellyfinForgotPasswordUrl',
      'movie4kEnabled',
      'series4kEnabled',
      'discoverRegion',
      'streamingRegion',
      'originalLanguage',
      'mediaServerType',
      'partialRequestsEnabled',
      'enableSpecialEpisodes',
      'cacheImages',
      'vapidPublic',
      'enablePushRegistration',
      'locale',
      'emailEnabled',
      'userEmailRequired',
      'newPlexLogin',
      'youtubeUrl',
    ],
  ),
  'Seerr 3.5.0': (
    'seerr/public_settings_seerr_3.5.0.json',
    '3.5.0',
    [
      'initialized',
      'applicationTitle',
      'applicationUrl',
      'hideAvailable',
      'hideBlocklisted',
      'hideRequested',
      'localLogin',
      'mediaServerLogin',
      'jellyfinExternalHost',
      'jellyfinForgotPasswordUrl',
      'movie4kEnabled',
      'series4kEnabled',
      'discoverRegion',
      'streamingRegion',
      'originalLanguage',
      'mediaServerType',
      'partialRequestsEnabled',
      'enableSpecialEpisodes',
      'cacheImages',
      'vapidPublic',
      'enablePushRegistration',
      'locale',
      'emailEnabled',
      'userEmailRequired',
      'newPlexLogin',
      'youtubeUrl',
      'versionCheck',
      'plexClientIdentifier',
    ],
  ),
};

Map<String, dynamic> _settings(String name) =>
    jsonFixtureMap(_fixtures[name]!.$1);

/// The Seerr 3.5.0 answer with [changes] laid over it.
Map<String, dynamic> _seerr(Map<String, dynamic> changes) => {
  ..._settings('Seerr 3.5.0'),
  ...changes,
};

const _plex = SeerrSignInMethod.plex;
const _jellyfin = SeerrSignInMethod.jellyfin;
const _quickConnect = SeerrSignInMethod.jellyfinQuickConnect;
const _emby = SeerrSignInMethod.emby;
const _local = SeerrSignInMethod.local;

void main() {
  group('the fixtures', () {
    for (final MapEntry(key: name, value: (path, _, fields))
        in _fixtures.entries) {
      test('$name has the fields its getter sends, and only those', () {
        expect(jsonFixtureMap(path).keys.toList(), fields);
      });
    }
  });

  group('the four families as they ship', () {
    test('Overseerr 1.35.0: Plex, then email', () {
      final facts = SeerrServerFacts.fromPublicSettings(
        _settings('Overseerr 1.35.0'),
        version: '1.35.0',
      );
      expect(facts.signIn.state, SeerrSignInState.open);
      expect(facts.signIn.offered, [_plex, _local]);
      expect(facts.family, SeerrFamily.overseerr);
      expect(facts.mediaServer, SeerrMediaServer.plex);
      expect(facts.title, 'Overseerr');
      expect(facts.partialRequestsEnabled, isTrue);
      expect(facts.emailEnabled, isFalse);
      expect(facts.jellyfinForgotPasswordUrl, isNull);
    });

    test('Jellyseerr 1.9.2: Jellyfin without a mediaServerLogin flag', () {
      final facts = SeerrServerFacts.fromPublicSettings(
        _settings('Jellyseerr 1.9.2'),
        version: '1.9.2',
      );
      // `mediaServerLogin` did not exist yet, so it is on.
      expect(facts.signIn.offered, [_jellyfin, _local]);
      expect(facts.family, SeerrFamily.jellyseerr);
      expect(facts.mediaServer, SeerrMediaServer.jellyfin);
      expect(facts.title, 'Jellyseerr');
    });

    test('Jellyseerr 2.7.3: Jellyfin, no Quick Connect yet', () {
      final facts = SeerrServerFacts.fromPublicSettings(
        _settings('Jellyseerr 2.7.3'),
        version: '2.7.3',
      );
      expect(facts.signIn.offered, [_jellyfin, _local]);
      expect(facts.family, SeerrFamily.jellyseerr);
    });

    test('Seerr 3.5.0: Jellyfin, a code from Jellyfin, then email', () {
      final facts = SeerrServerFacts.fromPublicSettings(
        _settings('Seerr 3.5.0'),
        version: '3.5.0',
      );
      expect(facts.signIn.offered, [_jellyfin, _quickConnect, _local]);
      expect(facts.family, SeerrFamily.seerr);
      expect(facts.title, 'Seerr');
      expect(facts.has4k(SeerrMediaKind.movie), isTrue);
      expect(facts.has4k(SeerrMediaKind.tv), isFalse);
      expect(facts.emailEnabled, isTrue);
    });
  });

  group('a server that is not set up offers nothing', () {
    // Its first media-server sign-in would create an admin and set it up
    // (`auth.ts:100-118`, `:334-430` at v3.5.0).
    for (final MapEntry(key: name, value: (_, version, _))
        in _fixtures.entries) {
      test(name, () {
        final methods = SeerrSignInMethods.fromPublicSettings({
          ..._settings(name),
          'initialized': false,
        }, version: version);
        expect(methods.state, SeerrSignInState.notSetUp);
        expect(methods.offered, isEmpty);
      });
    }

    test('nor does an answer without initialized', () {
      final methods = SeerrSignInMethods.fromPublicSettings(
        _seerr({})..remove('initialized'),
        version: '3.5.0',
      );
      expect(methods.state, SeerrSignInState.notSetUp);
    });
  });

  group('the variants', () {
    final rows = <(String, Map<String, dynamic>, String?, List<Object>)>[
      // Without a media server Seerr lets a Plex or Jellyfin sign-in through
      // to set one up (`auth.ts:82-86,263-269`): never offered.
      ('no media server', {'mediaServerType': 4}, '3.5.0', [_local]),
      (
        'no media server, no email',
        {'mediaServerType': 4, 'localLogin': false},
        '3.5.0',
        [],
      ),
      (
        'email turned off',
        {'localLogin': false},
        '3.5.0',
        [_jellyfin, _quickConnect],
      ),
      (
        'media server sign-in off',
        {'mediaServerLogin': false},
        '3.5.0',
        [_local],
      ),
      (
        'everything off',
        {'mediaServerLogin': false, 'localLogin': false},
        '3.5.0',
        [],
      ),
      // Quick Connect is Jellyfin's alone (`auth.ts:643`).
      ('Emby', {'mediaServerType': 3}, '3.5.0', [_emby, _local]),
      ('Plex', {'mediaServerType': 1}, '3.5.0', [_plex, _local]),
      (
        'Plex with its sign-in off',
        {'mediaServerType': 1, 'mediaServerLogin': false},
        '3.5.0',
        [_local],
      ),
      // Quick Connect arrived in 3.4.0: absent from `auth.ts` at v3.3.0.
      ('Seerr 3.4.0', {}, '3.4.0', [_jellyfin, _quickConnect, _local]),
      ('Seerr v3.4.1', {}, 'v3.4.1', [_jellyfin, _quickConnect, _local]),
      ('Seerr 4.0.0', {}, '4.0.0', [_jellyfin, _quickConnect, _local]),
      ('Seerr 3.3.0', {}, '3.3.0', [_jellyfin, _local]),
      // A build whose version says nothing is not offered a guess.
      ('a develop build', {}, 'develop-4f2a9c1', [_jellyfin, _local]),
      ('no version', {}, null, [_jellyfin, _local]),
      ('an unknown media server', {'mediaServerType': 9}, '3.5.0', [_local]),
    ];
    for (final (name, changes, version, offered) in rows) {
      test(name, () {
        final methods = SeerrSignInMethods.fromPublicSettings(
          _seerr(changes),
          version: version,
        );
        expect(methods.offered, offered);
        expect(
          methods.state,
          offered.isEmpty ? SeerrSignInState.turnedOff : SeerrSignInState.open,
        );
      });
    }

    test('Overseerr without email sign-in offers Plex alone', () {
      final methods = SeerrSignInMethods.fromPublicSettings({
        ..._settings('Overseerr 1.35.0'),
        'localLogin': false,
      }, version: '1.35.0');
      expect(methods.offered, [_plex]);
    });

    test('Jellyseerr 1.9.2 on Plex offers Plex', () {
      final methods = SeerrSignInMethods.fromPublicSettings({
        ..._settings('Jellyseerr 1.9.2'),
        'mediaServerType': 1,
      }, version: '1.9.2');
      expect(methods.offered, [_plex, _local]);
    });
  });

  group('the facts beside the methods', () {
    test('a reset link the operator set is read; an empty one is none', () {
      final facts = SeerrServerFacts.fromPublicSettings(
        _seerr({
          'jellyfinForgotPasswordUrl': 'https://jellyfin.example.com/reset',
        }),
        version: '3.5.0',
      );
      expect(
        facts.jellyfinForgotPasswordUrl,
        'https://jellyfin.example.com/reset',
      );
      expect(
        SeerrServerFacts.fromPublicSettings(
          _seerr({}),
        ).jellyfinForgotPasswordUrl,
        isNull,
      );
    });

    test('the media server the accounts come from is named when said', () {
      expect(
        SeerrServerFacts.fromPublicSettings(
          _seerr({'jellyfinServerName': 'Casa'}),
          version: '3.5.0',
        ).jellyfinServerName,
        'Casa',
      );
      expect(
        SeerrServerFacts.fromPublicSettings(_seerr({})).jellyfinServerName,
        isNull,
      );
    });

    test('a blank title falls back to Seerr', () {
      final facts = SeerrServerFacts.fromPublicSettings(
        _seerr({'applicationTitle': '  '}),
      );
      expect(facts.applicationTitle, isNull);
      expect(facts.title, 'Seerr');
      expect(
        SeerrServerFacts.fromPublicSettings(
          _seerr({'applicationTitle': 'Casa Requests'}),
        ).title,
        'Casa Requests',
      );
    });

    test('a flag that is missing or not a boolean is off', () {
      final facts = SeerrServerFacts.fromPublicSettings({
        'initialized': true,
        'mediaServerType': 2,
        'movie4kEnabled': 'true',
      });
      expect(facts.has4k(SeerrMediaKind.movie), isFalse);
      expect(facts.partialRequestsEnabled, isFalse);
      expect(facts.emailEnabled, isFalse);
      // No `localLogin`, so no email sign-in; Jellyfin is on by default.
      expect(facts.signIn.offered, [_jellyfin]);
    });

    test('the family needs a version past Jellyseerr 1.x', () {
      expect(
        SeerrServerFacts.fromPublicSettings(
          _seerr({}),
          version: 'develop-4f2a9c1',
        ).family,
        isNull,
      );
      expect(SeerrServerFacts.fromPublicSettings(_seerr({})).family, isNull);
      expect(
        SeerrServerFacts.fromPublicSettings(
          _seerr({}),
          version: '2.1.0',
        ).family,
        SeerrFamily.jellyseerr,
      );
    });

    test('printing the facts names no address and no identifier', () {
      final facts = SeerrServerFacts.fromPublicSettings(
        _seerr({
          'jellyfinForgotPasswordUrl': 'https://sentinel.example.com/reset',
          'jellyfinExternalHost': 'https://sentinel.example.net',
          'plexClientIdentifier': 'sentinel-client-identifier',
        }),
        version: '3.5.0',
      );
      expect(facts.toString(), isNot(contains('sentinel')));
      expect(facts.toString(), contains('jellyfin'));
    });

    test('the facts are a value', () {
      expect(
        SeerrServerFacts.fromPublicSettings(_seerr({}), version: '3.5.0'),
        SeerrServerFacts.fromPublicSettings(_seerr({}), version: '3.5.0'),
      );
      expect(
        SeerrServerFacts.fromPublicSettings(_seerr({}), version: '3.5.0'),
        isNot(
          SeerrServerFacts.fromPublicSettings(_seerr({}), version: '3.3.0'),
        ),
      );
    });
  });
}
