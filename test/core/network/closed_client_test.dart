/// Every client a provider closes when its connection's settings change, and
/// what a request still sent on it fails with: never the server's failure.
///
/// Each provider below owns its client and closes it on rebuild
/// (`ref.onDispose(client.close)`), which Riverpod runs the moment the
/// connection's transport changes, before anything reads the provider again.
/// Something still holding the old client (a screen's own future, an
/// action, a second request of the same read) then sends on a closed client:
/// the Dio clients refuse it before it leaves the device, and the WebSocket
/// ones fail what was waiting. [isClosedClientFailure] has to know every one
/// of those, and nothing else.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

import '../../test_helpers/profiles/profiles.dart';

/// Every service, each answering.
final _everyService = Profiles.p1
    .withConnection(WorldConnections.plex)
    .withConnection(WorldConnections.readarr)
    .withConnection(WorldConnections.transmission)
    .withConnection(WorldConnections.nzbget)
    .withConnection(WorldConnections.unraid)
    .withConnection(WorldConnections.npm);

/// A gateway header added on the connection's form: a change of transport
/// that rebuilds the client, and that the world's servers ignore.
Future<void> _changeSettings(ProviderContainer container, String id) {
  final settings = container.read(currentSettingsProvider);
  final instance = settings.instanceById(id)!;
  return container
      .read(settingsProvider.notifier)
      .updateSettings(
        settings.copyWithInstance(
          instance.copyWith(
            access: const CustomHeaders([(name: 'X-Gate', value: 'one')]),
          ),
        ),
      );
}

/// One provider that closes its client on rebuild, and a read through what
/// it hands out.
class _Holder<T> {
  const _Holder(this.name, this.id, this.provider, this.read);

  final String name;
  final String id;
  final ProviderBase<T> provider;
  final Future<Object?> Function(T held) read;

  /// The read sent on the client held across a settings change.
  Future<Object> heldAcrossAChange(ProviderContainer container) async {
    container.listen(provider, (_, _) {});
    final held = container.read(provider);
    await _changeSettings(container, id);
    try {
      await read(held);
    } catch (error) {
      return error;
    }
    fail('$name: the closed client answered');
  }

  /// The same read through the provider as it is now.
  Future<Object?> fresh(ProviderContainer container) =>
      read(container.read(provider));
}

final _dioClients = <_Holder<Object>>[
  _Holder(
    'Radarr',
    WorldIds.radarr,
    radarrServiceProvider,
    (s) => (s as dynamic).getMoviesOrThrow() as Future<Object?>,
  ),
  _Holder(
    'Sonarr',
    WorldIds.sonarr,
    sonarrServiceProvider,
    (s) => (s as dynamic).getSeriesOrThrow() as Future<Object?>,
  ),
  _Holder(
    'Lidarr',
    WorldIds.lidarr,
    lidarrServiceProvider,
    (s) => (s as dynamic).getArtistsOrThrow() as Future<Object?>,
  ),
  _Holder(
    'Readarr',
    WorldConnections.readarr.id,
    readarrServiceProvider,
    (s) => (s as dynamic).getAuthorsOrThrow() as Future<Object?>,
  ),
  _Holder(
    'Prowlarr',
    WorldIds.prowlarr,
    prowlarrServiceProvider,
    (s) => (s as dynamic).getHealth() as Future<Object?>,
  ),
  _Holder(
    'Bazarr',
    WorldIds.bazarr,
    bazarrServiceProvider,
    (s) => (s as dynamic).getBadges() as Future<Object?>,
  ),
  _Holder(
    'Seerr',
    WorldIds.seerr,
    seerrServiceProvider,
    (s) => (s as dynamic).testConnection() as Future<Object?>,
  ),
  _Holder(
    'qBittorrent',
    WorldIds.qbittorrent,
    qbittorrentClientForProvider(WorldIds.qbittorrent),
    (c) => (c as dynamic).getVersion() as Future<Object?>,
  ),
  _Holder(
    'Transmission',
    WorldIds.transmission,
    transmissionClientProvider,
    (c) => (c as dynamic).version() as Future<Object?>,
  ),
  _Holder(
    'SABnzbd',
    WorldIds.sabnzbd,
    sabnzbdClientProvider,
    (c) => (c as dynamic).getVersion() as Future<Object?>,
  ),
  _Holder(
    'NZBGet',
    WorldConnections.nzbget.id,
    nzbgetClientProvider,
    (c) => (c as dynamic).version() as Future<Object?>,
  ),
  _Holder(
    'Jellyfin',
    WorldIds.jellyfin,
    jellyfinClientProvider,
    (c) => (c as dynamic).getLibrariesOrThrow() as Future<Object?>,
  ),
  _Holder(
    'Plex',
    WorldIds.plex,
    plexClientProvider,
    (c) => (c as dynamic).getLibrariesOrThrow() as Future<Object?>,
  ),
  _Holder(
    'Nginx Proxy Manager',
    WorldConnections.npm.id,
    npmClientProvider,
    (c) => (c as dynamic).version() as Future<Object?>,
  ),
  _Holder(
    'Unraid',
    WorldConnections.unraid.id,
    unraidClientProvider,
    (c) => (c as dynamic).getArray() as Future<Object?>,
  ),
];

void main() {
  group('a request on a client closed by a settings change', () {
    for (final holder in _dioClients) {
      test(
        '${holder.name}: refused before it leaves, and known as such',
        () async {
          final harness = await ProfileHarness.start(_everyService);
          final container = harness.container();

          final error = await holder.heldAcrossAChange(container);

          expect(isClosedClientFailure(error), isTrue, reason: '$error');
          // The rebuilt client is the one that answers.
          await holder.fresh(container);
        },
      );
    }

    test('TrueNAS: a call waiting on the socket is failed as closed', () async {
      final harness = await ProfileHarness.start(
        _everyService.withLatency(
          WorldIds.truenas,
          const Duration(milliseconds: 200),
        ),
      );
      final container = harness.container();
      container.listen(truenasClientProvider, (_, _) {});
      final waiting = container
          .read(truenasClientProvider)
          .call('system.info')
          .then<Object?>((_) => null, onError: (Object error) => error);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _changeSettings(container, WorldIds.truenas);
      final error = await waiting;

      expect(error, isNotNull);
      expect(isClosedClientFailure(error), isTrue, reason: '$error');
    });

    test(
      'Dockge: a connect waiting on the socket is failed as closed',
      () async {
        final harness = await ProfileHarness.start(
          _everyService.withLatency(
            WorldIds.dockge,
            const Duration(milliseconds: 200),
          ),
        );
        final container = harness.container();
        container.listen(dockgeClientProvider, (_, _) {});
        final waiting = container
            .read(dockgeClientProvider)
            .ensureConnected()
            .then<Object?>((_) => null, onError: (Object error) => error);

        await Future<void>.delayed(const Duration(milliseconds: 50));
        await _changeSettings(container, WorldIds.dockge);
        final error = await waiting;

        expect(error, isNotNull);
        expect(isClosedClientFailure(error), isTrue, reason: '$error');
      },
    );
  });

  group('a provider whose read was caught by the change', () {
    test('reads again at once, on the rebuilt client', () async {
      final harness = await ProfileHarness.start(_everyService);
      final container = harness.container();
      // Something else reading Radarr keeps its client live.
      container.listen(radarrServiceProvider, (_, _) {});
      final gate = Completer<void>();
      final count = FutureProvider<int>((ref) async {
        // Holds what it read across a wait, as a read that waits on another
        // source or walks pages does.
        final service = ref.read(radarrServiceProvider);
        await gate.future;
        return (await service.getMoviesOrThrow()).length;
      }, retry: noProviderRetry);
      container.listen(count, (_, _) {});

      await _changeSettings(container, WorldIds.radarr);
      gate.complete();

      expect(await container.read(count.future), greaterThan(0));
    });

    test('the policy: at once, a few times, for that failure alone', () async {
      final dio = Dio()..close();
      Object? closed;
      try {
        await dio.get<dynamic>('http://nas.home.arpa:7878/api/v3/movie');
      } catch (error) {
        closed = error;
      }

      expect(noProviderRetry(0, closed!), Duration.zero);
      expect(noProviderRetry(2, closed), Duration.zero);
      expect(noProviderRetry(3, closed), isNull);
      expect(noProviderRetry(0, Exception('Radarr not configured')), isNull);
    });
  });

  test('a server that did not answer is not a closed client', () async {
    final harness = await ProfileHarness.start(
      _everyService.withBehaviour(
        WorldIds.radarr,
        ConnectionBehaviour.didNotAnswer,
      ),
    );
    final container = harness.container();
    Object? error;
    try {
      await container.read(radarrServiceProvider).getMoviesOrThrow();
    } catch (e) {
      error = e;
    }

    expect(error, isNotNull);
    expect(isClosedClientFailure(error), isFalse);
    expect(classifyConnectionFailure(error), ServiceFailureReason.unreachable);
  });
}
