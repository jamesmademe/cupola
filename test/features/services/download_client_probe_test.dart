/// The status probe of SABnzbd, NZBGet and Transmission reads the
/// connection's own client.
///
/// Their Queue pages ask the probe again every three seconds, and it used to
/// build a client for each ask: a new `Dio`, a new `HttpClient`, and on
/// Transmission the 409 handshake and the refused sign-in all over again. The
/// probe stays in the tick (a server that went quiet, or came back, is its
/// word, not the list's), so what is pinned here is what it asks *through*.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

import '../../test_helpers/profiles/profiles.dart';

/// One of the three, with how to reach its connection's client.
class _Client {
  const _Client(this.service, this.id, this.profile, this.clientOf);

  final ServiceKey service;
  final String id;
  final ConfigProfile profile;
  final Object Function(ProviderContainer container) clientOf;

  InstanceRef get ref => (service: service, instanceId: id);

  String get name => service.name;
}

final _clients = [
  _Client(
    ServiceKey.sabnzbd,
    WorldIds.sabnzbd,
    Profiles.p1,
    (c) => c.read(sabnzbdClientForProvider(WorldIds.sabnzbd)),
  ),
  _Client(
    ServiceKey.nzbget,
    'nzbget',
    Profiles.p1.withConnection(WorldConnections.nzbget),
    (c) => c.read(nzbgetClientForProvider('nzbget')),
  ),
  _Client(
    ServiceKey.transmission,
    WorldIds.transmission,
    Profiles.p1.withConnection(WorldConnections.transmission),
    (c) => c.read(transmissionClientForProvider(WorldIds.transmission)),
  ),
];

/// Counts the `HttpClient`s the app opens, and hands each to whatever was
/// installed before it (the profile's fake network).
class _CountingOverrides extends HttpOverrides {
  _CountingOverrides(this._inner);

  final HttpOverrides? _inner;
  int created = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    return _inner?.createHttpClient(context) ?? super.createHttpClient(context);
  }
}

_CountingOverrides _countHttpClients() {
  final previous = HttpOverrides.current;
  final counting = _CountingOverrides(previous);
  HttpOverrides.global = counting;
  addTearDown(() => HttpOverrides.global = previous);
  return counting;
}

Future<ServiceSummary> _probe(ProviderContainer container, _Client c) =>
    container.read(instanceSummaryProvider(c.ref).future);

/// The probe asked again, as the page's poll does on each tick.
Future<ServiceSummary> _tick(ProviderContainer container, _Client c) {
  container.invalidate(instanceSummaryProvider(c.ref));
  return _probe(container, c);
}

void main() {
  for (final c in _clients) {
    group('${c.name}\'s probe', () {
      test(
        'asks tick after tick through the connection\'s one client',
        () async {
          final harness = await ProfileHarness.start(c.profile);
          final container = harness.container();
          final counting = _countHttpClients();
          final client = c.clientOf(container);

          expect((await _probe(container, c)).isOnline, isTrue);
          final opened = counting.created;
          expect(opened, greaterThan(0), reason: 'the counting sees the first');

          for (var tick = 0; tick < 4; tick++) {
            expect((await _tick(container, c)).isOnline, isTrue);
          }

          expect(
            counting.created,
            opened,
            reason: 'no new Dio and no new HttpClient for a tick',
          );
          expect(identical(c.clientOf(container), client), isTrue);
        },
      );

      test(
        'still tells a server that went quiet from one that came back',
        () async {
          final harness = await ProfileHarness.start(c.profile);
          final container = harness.container();

          expect((await _probe(container, c)).isOnline, isTrue);

          harness.network.behave(c.id, ConnectionBehaviour.didNotAnswer);
          final dark = await _tick(container, c);
          expect(dark.didNotAnswer, isTrue);

          harness.network.behave(c.id, ConnectionBehaviour.answers);
          final back = await _tick(container, c);
          expect(
            back.isOnline,
            isTrue,
            reason: 'the banner clears on recovery',
          );
        },
      );

      test('follows its connection\'s route: a new client, and the address '
          'away', () async {
        const away = 'http://away.example.net:9999';
        final connection = c.profile.connection(c.id);
        final harness = await ProfileHarness.start(
          c.profile.withConnection(
            ProfileConnection(
              connection.instance.copyWith(
                away: const ConnectionAddress(url: away),
              ),
            ),
          ),
        );
        final container = harness.container();
        final home = c.clientOf(container);
        expect((await _probe(container, c)).isOnline, isTrue);

        await container
            .read(connectionRoutesProvider.notifier)
            .set(c.id, ConnectionRoute.away);

        expect(
          identical(c.clientOf(container), home),
          isFalse,
          reason: 'a client is built for the address it reaches',
        );
        final summary = await _probe(container, c);
        expect(summary.isOnline, isFalse, reason: 'nothing answers there');
        expect(harness.network.requests.last.uri.host, 'away.example.net');
      });
    });
  }

  test(
    'Transmission\'s probe pays the 409 handshake once, not per tick',
    () async {
      final c = _clients.last;
      final harness = await ProfileHarness.start(c.profile);
      final container = harness.container();

      await _probe(container, c);
      for (var tick = 0; tick < 4; tick++) {
        await _tick(container, c);
      }

      final handshakes = harness.network
          .requestsTo(c.id)
          .where((request) => !request.headers.containsKey(_sessionIdHeader));
      expect(handshakes, hasLength(1));
      expect(harness.network.requestsTo(c.id), hasLength(1 + 5));
    },
  );

  test(
    'a wrong Transmission password is sent once, not on every tick',
    () async {
      final c = _clients.last;
      final harness = await ProfileHarness.start(
        c.profile.withBehaviour(c.id, ConnectionBehaviour.refusesKey),
      );
      final container = harness.container();

      final first = await _probe(container, c);
      expect(first.failureReason, ServiceFailureReason.unauthorized);
      for (var tick = 0; tick < 4; tick++) {
        final again = await _tick(container, c);
        // Still refused, read from the client's hold rather than asked again:
        // the daemon's anti-brute-force counts every one it is sent.
        expect(again.failureReason, ServiceFailureReason.unauthorized);
      }

      expect(harness.network.requestsTo(c.id), hasLength(1));
    },
  );
}

const _sessionIdHeader = 'x-transmission-session-id';
