import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/pairing/domain/pair_link.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final closes = DateTime.utc(2026, 10, 15, 20, 41, 30);
  PairLink link({String host = '192.168.1.20'}) => PairLink(
    host: InternetAddress(host),
    port: 47213,
    key: key,
    closesAt: closes,
  );

  group('the link', () {
    test('round-trips through its URI', () {
      final uri = link().toUri();
      expect(uri.scheme, 'cupola');
      expect(uri.host, 'pair');
      expect(uri.queryParameters['v'], '1');
      expect(uri.queryParameters['h'], '192.168.1.20:47213');
      expect(uri.queryParameters['k'], hasLength(43));
      expect(PairLink.fromQuery(uri.queryParameters), link());
    });

    test('stays short enough for a code read off a screen', () {
      expect(link().toLink().length, lessThan(110));
    });

    test('never prints its key', () {
      final text = link().toString();
      expect(text, 'PairLink(192.168.1.20:47213)');
      expect(text, isNot(contains(link().toUri().queryParameters['k']!)));
    });

    test('says it has closed only once the clocks can no longer disagree', () {
      expect(link().hasClosedBy(closes), isFalse);
      expect(
        link().hasClosedBy(closes.add(const Duration(seconds: 29))),
        isFalse,
      );
      expect(
        link().hasClosedBy(closes.add(const Duration(seconds: 31))),
        isTrue,
      );
    });
  });

  group('reading a link', () {
    Map<String, String> query([Map<String, String> changes = const {}]) => {
      ...link().toUri().queryParameters,
      ...changes,
    };

    test('is recognised as the system hands it over and once routed', () {
      expect(PairLink.isPairUri(link().toUri()), isTrue);
      expect(
        PairLink.isPairUri(Uri(path: '/pair', queryParameters: query())),
        isTrue,
      );
      expect(PairLink.isPairUri(Uri.parse('cupola://invite?v=1')), isFalse);
      expect(PairLink.isPairUri(Uri.parse('/pair')), isFalse);
    });

    test('refuses another version', () {
      expect(PairLink.fromQuery(query({'v': '2'})), isNull);
    });

    test('refuses an address off the home network, or a name', () {
      for (final host in [
        '8.8.8.8',
        '100.74.92.3',
        '169.254.10.2',
        'nas.local',
        '[fd00::1]',
      ]) {
        expect(
          PairLink.fromQuery(query({'h': '$host:47213'})),
          isNull,
          reason: host,
        );
      }
      for (final host in [
        '10.0.0.4',
        '172.20.1.9',
        '192.168.50.2',
        '127.0.0.1',
      ]) {
        expect(
          PairLink.fromQuery(query({'h': '$host:47213'})),
          isNotNull,
          reason: host,
        );
      }
    });

    test('refuses a port out of range, a key cut short, no closing time', () {
      expect(PairLink.fromQuery(query({'h': '192.168.1.20:80'})), isNull);
      expect(PairLink.fromQuery(query({'h': '192.168.1.20'})), isNull);
      expect(
        PairLink.fromQuery(query({'k': query()['k']!.substring(1)})),
        isNull,
      );
      expect(PairLink.fromQuery(query({'k': '+' * 43})), isNull);
      expect(PairLink.fromQuery({...query()}..remove('x')), isNull);
      expect(PairLink.fromQuery(query({'x': 'soon'})), isNull);
    });

    test('finds a link inside a message', () {
      final text = 'Here: ${link().toLink()} (two minutes)';
      expect(PairLink.tryParse(text), link());
      expect(PairLink.mentionsPair(text), isTrue);
      expect(PairLink.tryParse('cupola://pair?v=1&h=8.8.8.8:4000'), isNull);
      expect(PairLink.mentionsPair('http://nas:5055'), isFalse);
    });
  });

  group('an invite shown in person', () {
    PairLink invite() => PairLink(
      host: InternetAddress('192.168.1.20'),
      port: 47213,
      key: key,
      closesAt: closes,
      invite: true,
    );

    test('says so in its link, and reads back as one', () {
      final uri = invite().toUri();
      expect(uri.queryParameters['t'], 'invite');
      expect(PairLink.fromQuery(uri.queryParameters), invite());
      expect(PairLink.fromQuery(uri.queryParameters)!.invite, isTrue);
      expect(link().toUri().queryParameters, isNot(contains('t')));
      expect(invite(), isNot(link()));
    });

    test('a mark it does not know refuses the link', () {
      final query = {...link().toUri().queryParameters, 't': 'everything'};
      expect(PairLink.fromQuery(query), isNull);
    });

    test('prints that it is one, never its key', () {
      expect(invite().toString(), 'PairLink(192.168.1.20:47213, invite)');
    });
  });
}
