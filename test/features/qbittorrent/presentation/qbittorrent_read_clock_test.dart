import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// Answers `/torrents/info` with one torrent, or fails it as a refused
/// connection, and remembers nothing else.
class _Adapter implements HttpClientAdapter {
  bool down = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (down) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
      );
    }
    final body = jsonEncode([
      {'hash': 'aaa', 'name': 'Ubuntu.ISO', 'state': 'downloading', 'eta': 60},
    ]);
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(body)),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

final _settings = SettingsModel(
  instances: [
    const ServiceInstance(
      id: 'home',
      service: ServiceKey.qbittorrent,
      url: 'http://home.qb.test',
    ),
    const ServiceInstance(
      id: 'seedbox',
      service: ServiceKey.qbittorrent,
      url: 'http://seedbox.qb.test',
    ),
  ],
);

String _key(String connection) =>
    queueReadKey(ServiceKey.qbittorrent, connection);

void main() {
  late _Adapter adapter;
  late DateTime now;
  late ReadClock clock;

  setUp(() {
    adapter = _Adapter();
    now = DateTime(2026, 10, 12, 9);
    clock = ReadClock(now: () => now);
  });

  ProviderContainer containerOn(String lens) {
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => _settings),
        initialActiveInstancesProvider.overrideWithValue({
          ServiceKey.qbittorrent: lens,
        }),
        readClockProvider.overrideWithValue(clock),
        qbittorrentServiceProvider.overrideWith((ref) {
          final dio = Dio(BaseOptions(baseUrl: 'http://qb.test'))
            ..httpClientAdapter = adapter;
          return QbittorrentService(
            QbittorrentClient(url: 'http://qb.test', dio: dio),
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the torrent list is noted as read', () {
    test(
      'when the whole list comes back, for the connection it came from',
      () async {
        final container = containerOn('seedbox');

        await container.read(allTorrentsProvider.future);

        expect(clock.at(_key('seedbox')), now);
        expect(clock.at(_key('home')), isNull);
      },
    );

    test('and a list that failed notes nothing', () async {
      final container = containerOn('home');
      adapter.down = true;

      await expectLater(
        container.read(allTorrentsProvider.future),
        throwsA(isA<DioException>()),
      );

      expect(clock.at(_key('home')), isNull);
    });

    test('and a failure after a read leaves the time of the read', () async {
      final container = containerOn('home');
      await container.read(allTorrentsProvider.future);
      final readAt = now;

      now = now.add(const Duration(minutes: 6));
      adapter.down = true;
      container.invalidate(allTorrentsProvider);
      await expectLater(
        container.read(allTorrentsProvider.future),
        throwsA(isA<DioException>()),
      );

      expect(clock.at(_key('home')), readAt);
    });

    test('through the page provider when the filter is all', () async {
      final container = containerOn('home');

      await container.read(torrentsProvider.future);

      expect(clock.at(_key('home')), now);
    });

    test('through the page provider when the filter asks the server', () async {
      final container = containerOn('home');
      container.read(torrentFilterProvider.notifier).state =
          TorrentFilter.downloading;

      await container.read(torrentsProvider.future);

      expect(clock.at(_key('home')), now);
    });

    test('and narrowing the page list again is not a read', () async {
      // The list the page draws is derived from the one already in hand when
      // the filter is `all`: deriving it again later, from an answer that has
      // since gone stale, must not make it look fresh.
      final container = containerOn('home');
      await container.read(torrentsProvider.future);
      final readAt = now;

      now = now.add(const Duration(minutes: 6));
      container.read(torrentSearchQueryProvider.notifier).state = 'ubuntu';
      await container.read(torrentsProvider.future);

      expect(clock.at(_key('home')), readAt);
    });
  });
}
