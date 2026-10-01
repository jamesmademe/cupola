/// A refused qBittorrent sign-in is held for the connection, not for the one
/// client that met it.
///
/// qBittorrent bans an address after five failed sign-ins. A refusal held only
/// by a client object was forgotten by every new client: each launch of the
/// app, and any check run in the background, which builds clients of its own,
/// spent another of the five on credentials already refused.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_refusal_store.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/profiles/profiles.dart';

const _loginPath = '/api/v2/auth/login';
const _url = 'https://qb.example.com';

/// A WebUI that answers every login with [loginStatus] and counts them.
class _WebUi implements HttpClientAdapter {
  _WebUi(this.loginStatus);

  int loginStatus;
  int logins = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final isLogin = options.path == _loginPath;
    if (isLogin) logins++;
    return ResponseBody.fromBytes(
      utf8.encode(isLogin ? '' : 'v5.1.0'),
      isLogin ? loginStatus : 200,
      headers: {
        Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
      },
    );
  }
}

QbittorrentClient _client(
  _WebUi webUi,
  QbittorrentRefusalStore store, {
  String connectionId = 'qb-home',
  String password = 'wrong-password',
}) {
  final dio = Dio(BaseOptions(baseUrl: _url))..httpClientAdapter = webUi;
  final client = QbittorrentClient(
    url: _url,
    username: 'admin',
    password: password,
    dio: dio,
    connectionId: connectionId,
    refusalStore: store,
  );
  addTearDown(client.close);
  return client;
}

final Matcher _refused = throwsA(
  isA<QbittorrentException>().having(
    (e) => e.reason,
    'reason',
    ServiceFailureReason.unauthorized,
  ),
);

/// A secure storage that cannot be read or written.
class _BrokenSecureStore implements SecureSettingsStore {
  @override
  Future<String?> read({required String key}) async =>
      throw Exception('keychain locked');

  @override
  Future<void> write({required String key, required String value}) async =>
      throw Exception('keychain locked');

  @override
  Future<void> delete({required String key}) async =>
      throw Exception('keychain locked');

  @override
  Future<void> deleteAll() async => throw Exception('keychain locked');
}

void main() {
  group('a refused sign-in is held for the connection', () {
    test('a new client of the connection does not send it again', () async {
      final store = MemoryQbittorrentRefusalStore();
      final webUi = _WebUi(401);

      await expectLater(_client(webUi, store).getVersion(), _refused);
      expect(webUi.logins, 1);

      // The next launch, or a check in the background: a client of its own.
      final next = _client(webUi, store);
      await expectLater(next.getVersion(), _refused);
      expect(await next.authenticate(), isFalse);
      expect(next.loginRefused, isTrue);
      expect(webUi.logins, 1);
    });

    test(
      'new credentials are asked, and a sign-in that works lifts the hold',
      () async {
        final store = MemoryQbittorrentRefusalStore();
        final webUi = _WebUi(401);
        await expectLater(_client(webUi, store).getVersion(), _refused);

        webUi.loginStatus = 204;
        final fixed = _client(webUi, store, password: 'right-password');
        expect(await fixed.getVersion(), 'v5.1.0');
        expect(webUi.logins, 2);
        expect(await store.read('qb-home'), isNull);
      },
    );

    test('a refusal on one connection holds nothing on another', () async {
      final store = MemoryQbittorrentRefusalStore();
      final webUi = _WebUi(401);
      await expectLater(_client(webUi, store).getVersion(), _refused);

      webUi.loginStatus = 204;
      final seedbox = _client(webUi, store, connectionId: 'qb-seedbox');
      expect(await seedbox.getVersion(), 'v5.1.0');
      expect(webUi.logins, 2);
      expect(await store.read('qb-home'), isNotNull);
    });

    test(
      'a person asking again lifts it for every client of the connection',
      () async {
        final store = MemoryQbittorrentRefusalStore();
        final webUi = _WebUi(401);
        final first = _client(webUi, store);
        await expectLater(first.getVersion(), _refused);

        first.clearLoginRefusal();
        await pumpEventQueue();
        expect(await store.read('qb-home'), isNull);

        // The password was put back at the server; a new client asks once.
        webUi.loginStatus = 204;
        expect(await _client(webUi, store).getVersion(), 'v5.1.0');
        expect(webUi.logins, 2);
      },
    );

    test('a client of no connection keeps the old, per-client hold', () async {
      final store = MemoryQbittorrentRefusalStore();
      final webUi = _WebUi(401);
      final dio = Dio(BaseOptions(baseUrl: _url))..httpClientAdapter = webUi;
      final typed = QbittorrentClient(
        url: _url,
        username: 'admin',
        password: 'wrong-password',
        dio: dio,
        refusalStore: store,
      );
      addTearDown(typed.close);

      await expectLater(typed.getVersion(), _refused);
      await expectLater(typed.getVersion(), _refused);
      expect(webUi.logins, 1);
      expect(await store.read(''), isNull);
    });
  });

  group('the secure store', () {
    test('keeps a mark of the credentials, never the credentials', () async {
      final secure = FakeSecureSettingsStore();
      final webUi = _WebUi(401);
      await expectLater(
        _client(webUi, SecureQbittorrentRefusalStore(secure)).getVersion(),
        _refused,
      );

      expect(secure.entries, hasLength(1));
      final stored = secure.entries.values.single;
      expect(stored, isNot(contains('wrong-password')));
      expect(stored, isNot(contains('admin')));
      expect(stored, isNot(contains('qb.example.com')));
      expect(jsonDecode(stored), containsPair('kind', 'credentials'));
    });

    test(
      'a store that cannot be read holds nothing and breaks nothing',
      () async {
        final webUi = _WebUi(401);
        final store = SecureQbittorrentRefusalStore(_BrokenSecureStore());
        final client = _client(webUi, store);

        await expectLater(client.getVersion(), _refused);
        await expectLater(client.getVersion(), _refused);
        expect(webUi.logins, 1, reason: 'the client still holds it itself');

        webUi.loginStatus = 204;
        expect(
          await _client(webUi, store, password: 'right-password').getVersion(),
          'v5.1.0',
        );
      },
    );
  });

  test('a relaunch of the app does not spend another attempt', () async {
    final secure = FakeSecureSettingsStore();
    final harness = await ProfileHarness.start(
      Profiles.p1.withBehaviour(
        WorldIds.qbittorrent,
        ConnectionBehaviour.refusesKey,
      ),
      overrides: [
        qbittorrentRefusalStoreProvider.overrideWithValue(
          SecureQbittorrentRefusalStore(secure),
        ),
      ],
    );
    const qb = (
      service: ServiceKey.qbittorrent,
      instanceId: WorldIds.qbittorrent,
    );
    int signIns() => harness.network
        .requestsTo(WorldIds.qbittorrent)
        .where((request) => request.path == _loginPath)
        .length;

    final firstRun = harness.container();
    await firstRun.read(instanceSummaryProvider(qb).future);
    expect(signIns(), 1);
    firstRun.dispose();

    final secondRun = harness.container();
    final summary = await secondRun.read(instanceSummaryProvider(qb).future);
    expect(summary.failureReason, ServiceFailureReason.unauthorized);
    expect(signIns(), 1);
  });
}
