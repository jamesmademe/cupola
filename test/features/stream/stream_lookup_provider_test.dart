import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_lookup_provider.dart';

import '../../test_helpers/settings_scope.dart';

StreamItem _item(String id, {StreamExternalIds ids = StreamExternalIds.none}) =>
    StreamItem(
      id: id,
      title: 'Nosferatu',
      subtitle: '1922',
      kind: StreamItemKind.movie,
      posterPath: null,
      year: 1922,
      runtimeMs: null,
      isPlayed: false,
      resumeOffsetMs: null,
      unplayedChildCount: null,
      externalIds: ids,
    );

/// A server client that answers the join with whatever the test scripted —
/// including an answer it did not check, which is the case the provider's gate
/// exists for.
class _ScriptedJoin implements StreamServerClient {
  _ScriptedJoin(this.answer);

  final StreamItem? answer;

  final List<({String? tmdbId, StreamItemKind? kind})> asked = [];

  @override
  Future<StreamItem?> findByExternalId({
    String? tmdbId,
    String? tvdbId,
    String? imdbId,
    StreamItemKind? kind,
    String? title,
    int? year,
    CancelToken? cancelToken,
  }) async {
    asked.add((tmdbId: tmdbId, kind: kind));
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<StreamMatch?> _match(
  StreamServerClient jellyfin, {
  StreamServerClient? plex,
  StreamItemKind? kind,
}) async {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith(
        (ref) => settingsWith(
          jellyfinUrl: 'http://jelly.local:8096',
          jellyfinApiKey: 'key',
          plexUrl: plex == null ? '' : 'http://plex.local:32400',
          plexToken: plex == null ? '' : 'token',
        ),
      ),
      jellyfinServerProvider.overrideWithValue(jellyfin),
      if (plex != null) plexServerProvider.overrideWithValue(plex),
    ],
  );
  addTearDown(container.dispose);
  final key = (
    tmdbId: '653',
    tvdbId: null,
    imdbId: null,
    kind: kind,
    title: null,
    year: null,
  );
  final subscription = container.listen(streamMatchProvider(key), (_, _) {});
  addTearDown(subscription.close);
  return container.read(streamMatchProvider(key).future);
}

void main() {
  group('streamMatchProvider', () {
    test('an answer whose own ids agree is shown', () async {
      final match = await _match(
        _ScriptedJoin(
          _item('right', ids: const StreamExternalIds(tmdb: '653')),
        ),
      );

      expect(match?.service, ServiceKey.jellyfin);
      expect(match?.item.id, 'right');
    });

    test('an unchecked wrong answer from a client is refused', () async {
      // The client handed back a row naming another film. Rendering it would
      // put "On Jellyfin · Ready to watch" on the page with a link to the
      // wrong title; silence is the only honest answer.
      final match = await _match(
        _ScriptedJoin(_item('wrong', ids: const StreamExternalIds(tmdb: '1'))),
      );

      expect(match, isNull);
    });

    test('an answer with no ids of its own is refused too', () async {
      final match = await _match(_ScriptedJoin(_item('bare')));

      expect(match, isNull);
    });

    test('a refused answer lets the next server speak', () async {
      final match = await _match(
        _ScriptedJoin(_item('wrong', ids: const StreamExternalIds(tmdb: '1'))),
        plex: _ScriptedJoin(
          _item('on-plex', ids: const StreamExternalIds(tmdb: '653')),
        ),
      );

      expect(match?.service, ServiceKey.plex);
      expect(match?.item.id, 'on-plex');
    });

    test('the kind travels to the client', () async {
      final jellyfin = _ScriptedJoin(null);
      await _match(jellyfin, kind: StreamItemKind.movie);

      expect(jellyfin.asked.single, (
        tmdbId: '653',
        kind: StreamItemKind.movie,
      ));
    });
  });
}
