import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

import '../../../test_helpers/settings_scope.dart';

/// Every service client provider owns a live `Dio`, and several own more than
/// that: qBittorrent holds the WebUI SID cookie, NPM holds a bearer token that
/// exists nowhere else. Rebuilding one is therefore not free, it drops a
/// session.
///
/// These providers used to `ref.watch(currentSettingsProvider)` whole, so *any*
/// settings write rebuilt *every* client: changing the theme, editing a
/// different service's address, finishing onboarding. Five of them also had no
/// `onDispose`, so the client they replaced was never closed: a transport
/// leak on every rebuild.
///
/// Each provider now watches a `select` of just its own transport identity
/// (address, credential, pinned certificate) and closes the outgoing client. The
/// two properties below are what that buys, and neither was covered before:
/// unrelated writes must not disturb a live client, and the service's own
/// address must.
void main() {
  /// A container with every service configured, mutable through
  /// `settingsProvider.notifier`.
  Future<ProviderContainer> containerWith(List<ServiceKey> configured) async {
    final container = ProviderContainer(
      overrides: await settingsScopeOverrides(configured: configured),
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Providers keyed by the service whose settings they are supposed to follow.
  /// Read through `Object Function(ProviderContainer)` so one table can hold
  /// providers of unrelated types.
  final clients =
      <String, ({ServiceKey key, Object Function(ProviderContainer) read})>{
        'radarr': (
          key: ServiceKey.radarr,
          read: (c) => c.read(radarrServiceProvider),
        ),
        'sonarr': (
          key: ServiceKey.sonarr,
          read: (c) => c.read(sonarrServiceProvider),
        ),
        'lidarr': (
          key: ServiceKey.lidarr,
          read: (c) => c.read(lidarrServiceProvider),
        ),
        'seerr': (
          key: ServiceKey.seerr,
          read: (c) => c.read(seerrServiceProvider),
        ),
        'bazarr': (
          key: ServiceKey.bazarr,
          read: (c) => c.read(bazarrServiceProvider),
        ),
        'prowlarr': (
          key: ServiceKey.prowlarr,
          read: (c) => c.read(prowlarrServiceProvider),
        ),
        'readarr': (
          key: ServiceKey.readarr,
          read: (c) => c.read(readarrServiceProvider),
        ),
        'qbittorrent': (
          key: ServiceKey.qbittorrent,
          read: (c) => c.read(qbittorrentServiceProvider),
        ),
        'sabnzbd': (
          key: ServiceKey.sabnzbd,
          read: (c) => c.read(sabnzbdClientProvider),
        ),
        'nzbget': (
          key: ServiceKey.nzbget,
          read: (c) => c.read(nzbgetClientProvider),
        ),
        'transmission': (
          key: ServiceKey.transmission,
          read: (c) => c.read(transmissionClientProvider),
        ),
        'npm': (
          key: ServiceKey.nginxProxyManager,
          read: (c) => c.read(npmClientProvider),
        ),
        'unraid': (
          key: ServiceKey.unraid,
          read: (c) => c.read(unraidClientProvider),
        ),
        'dockge': (
          key: ServiceKey.dockge,
          read: (c) => c.read(dockgeClientProvider),
        ),
        'plex': (key: ServiceKey.plex, read: (c) => c.read(plexClientProvider)),
        'jellyfin': (
          key: ServiceKey.jellyfin,
          read: (c) => c.read(jellyfinClientProvider),
        ),
        'truenas': (
          key: ServiceKey.truenas,
          read: (c) => c.read(truenasClientProvider),
        ),
      };

  group('an unrelated settings write leaves the client alone', () {
    for (final entry in clients.entries) {
      test('${entry.key} survives a theme change', () async {
        final container = await containerWith([entry.value.key]);
        final before = entry.value.read(container);

        // Something with no bearing on any transport.
        final settings = container.read(currentSettingsProvider);
        await container
            .read(settingsProvider.notifier)
            .updateSettings(settings.copyWith(region: 'IT'));

        expect(
          identical(entry.value.read(container), before),
          isTrue,
          reason:
              '${entry.key} was rebuilt by a settings write it does not depend '
              'on. Watching the whole SettingsModel would do this; a select of '
              'its own transport identity must not.',
        );
      });

      test('${entry.key} survives another service being edited', () async {
        // Configure a second service so there is a neighbour to disturb.
        final neighbour = entry.value.key == ServiceKey.radarr
            ? ServiceKey.sonarr
            : ServiceKey.radarr;
        final container = await containerWith([entry.value.key, neighbour]);
        final before = entry.value.read(container);

        final settings = container.read(currentSettingsProvider);
        await container
            .read(settingsProvider.notifier)
            .updateSettings(
              settings.copyWithService(
                neighbour,
                url: 'https://moved.example.com',
              ),
            );

        expect(
          identical(entry.value.read(container), before),
          isTrue,
          reason:
              '${entry.key} was rebuilt because ${neighbour.title} changed '
              'address. Each client must follow only its own settings.',
        );
      });
    }
  });

  group('the service own address still rebuilds its client', () {
    for (final entry in clients.entries) {
      test('${entry.key} is rebuilt when its URL changes', () async {
        final container = await containerWith([entry.value.key]);
        final before = entry.value.read(container);

        final settings = container.read(currentSettingsProvider);
        await container
            .read(settingsProvider.notifier)
            .updateSettings(
              settings.copyWithService(
                entry.value.key,
                url: 'https://elsewhere.example.com',
              ),
            );

        expect(
          identical(entry.value.read(container), before),
          isFalse,
          reason:
              '${entry.key} kept talking to the old address after its URL was '
              'changed. The select must include the URL.',
        );
      });
    }
  });

  group('the outgoing client is closed', () {
    // Asserted by swapping in an adapter that records its own close(), NOT by
    // watching a request fail: a request to an unreachable host throws
    // DioException whether or not anything was ever closed, so that assertion
    // passes on the very leak it is meant to catch, and it would put a real
    // socket in an offline test suite.
    test('a rebuild closes the Dio it replaces', () async {
      final container = await containerWith([ServiceKey.radarr]);
      final adapter = _RecordingAdapter();
      container.read(radarrServiceProvider).client.dio.httpClientAdapter =
          adapter;

      final settings = container.read(currentSettingsProvider);
      await container
          .read(settingsProvider.notifier)
          .updateSettings(
            settings.copyWithService(
              ServiceKey.radarr,
              url: 'https://elsewhere.example.com',
            ),
          );
      // Force the rebuild, which is what disposes the previous one.
      container.read(radarrServiceProvider);

      expect(
        adapter.closed,
        isTrue,
        reason:
            'the replaced ApiClient kept its Dio open: every settings change '
            'would leak one.',
      );
    });

    test('disposing the container closes the live Dio', () async {
      final container = ProviderContainer(
        overrides: await settingsScopeOverrides(
          configured: const [ServiceKey.radarr],
        ),
      );
      final adapter = _RecordingAdapter();
      container.read(radarrServiceProvider).client.dio.httpClientAdapter =
          adapter;

      container.dispose();

      expect(adapter.closed, isTrue);
    });
  });
}

/// Records `close()` instead of performing any I/O, so the assertion is about
/// lifecycle and the test stays offline.
class _RecordingAdapter implements HttpClientAdapter {
  bool closed = false;

  @override
  void close({bool force = false}) => closed = true;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw UnsupportedError('offline test: no request should be made');
}
