import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/stream/domain/stream_players.dart';

/// The links each Jellyfin app takes for an item, exactly, and the platforms
/// each one exists on. Pure: nothing here asks a platform anything.
void main() {
  final webUrl = Uri.parse(
    'https://jellyfin.example.com/web/index.html#!/details?id=abc',
  );

  group('the links', () {
    test('the browser opens the web client link it was given', () {
      expect(StreamPlayer.web.link(itemId: 'abc', webUrl: webUrl), webUrl);
    });

    test('Swiftfin takes the server, the viewer and the item', () {
      expect(
        StreamPlayer.swiftfin.link(
          itemId: 'item1',
          serverId: 'srv1',
          userId: 'usr1',
        ),
        Uri.parse('swiftfin://srv1/usr1/item/item1'),
      );
    });

    test('Swiftfin is not offered without the server or the viewer', () {
      expect(
        StreamPlayer.swiftfin.link(itemId: 'item1', userId: 'usr1'),
        isNull,
        reason: 'no server id',
      );
      expect(
        StreamPlayer.swiftfin.link(itemId: 'item1', serverId: 'srv1'),
        isNull,
        reason: 'no viewer id',
      );
      expect(
        StreamPlayer.swiftfin.link(
          itemId: 'item1',
          serverId: '',
          userId: 'usr1',
        ),
        isNull,
        reason: 'an empty server id is no id',
      );
    });

    test('Streamyfin opens the play screen of the item', () {
      expect(
        StreamPlayer.streamyfin.link(itemId: 'item1'),
        Uri.parse('streamyfin://topshelf/play?id=item1'),
      );
    });

    test('Fladder opens the details of the item, with three slashes', () {
      final link = StreamPlayer.fladder.link(itemId: 'item1');
      expect(link, isNotNull);
      expect(link.toString(), 'fladder:///details?id=item1');
    });

    test('an item id is encoded where it sits in a link', () {
      expect(
        StreamPlayer.streamyfin.link(itemId: 'a b&c').toString(),
        'streamyfin://topshelf/play?id=a+b%26c',
      );
    });

    test('the apps need no web link, and the browser needs no app id', () {
      expect(
        StreamPlayer.streamyfin.link(itemId: 'x', webUrl: webUrl)?.scheme,
        'streamyfin',
      );
      expect(StreamPlayer.web.link(itemId: 'x'), isNull);
    });
  });

  group('the platforms', () {
    test('Swiftfin is iOS only', () {
      expect(StreamPlayer.swiftfin.platforms, {TargetPlatform.iOS});
    });

    test('Streamyfin and Fladder are on the phones', () {
      for (final player in [StreamPlayer.streamyfin, StreamPlayer.fladder]) {
        expect(player.platforms, {TargetPlatform.iOS, TargetPlatform.android});
      }
    });

    test('the browser is on every platform', () {
      expect(StreamPlayer.web.platforms, containsAll(TargetPlatform.values));
    });
  });

  group('the probe and the scheme', () {
    test('each app is asked about its scheme, with nothing after it', () {
      expect(StreamPlayer.swiftfin.probe, Uri.parse('swiftfin://'));
      expect(StreamPlayer.streamyfin.probe, Uri.parse('streamyfin://'));
      expect(StreamPlayer.fladder.probe, Uri.parse('fladder://'));
    });

    test('the browser has no scheme to ask about: it is always there', () {
      expect(StreamPlayer.web.scheme, isNull);
      expect(StreamPlayer.web.probe, isNull);
    });
  });

  test('every player has the name and the line the sheet shows', () {
    expect(StreamPlayer.web.label, 'Jellyfin in the browser');
    expect(StreamPlayer.web.line, 'In your browser');
    expect(StreamPlayer.swiftfin.label, 'Swiftfin');
    expect(StreamPlayer.swiftfin.line, 'Opens its page');
    expect(StreamPlayer.streamyfin.label, 'Streamyfin');
    expect(StreamPlayer.streamyfin.line, 'Plays from where you stopped');
    expect(StreamPlayer.fladder.label, 'Fladder');
    expect(StreamPlayer.fladder.line, 'Opens its page');
  });
}
