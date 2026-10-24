import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/route_poster.dart';

void main() {
  setUp(RoutePoster.reset);
  tearDown(RoutePoster.reset);

  group('a poster a route may preload', () {
    test('public artwork over https', () {
      const tmdb = 'https://image.tmdb.org/t/p/w342/abc.jpg';
      expect(RoutePoster.accept(tmdb), tmdb);
      expect(
        RoutePoster.accept('https://artworks.thetvdb.com/banners/x.jpg'),
        isNotNull,
      );
    });

    test('the address of a configured connection, even in cleartext', () {
      RoutePoster.update([
        'http://192.168.1.10:8096',
        'https://jf.example.com',
      ]);

      expect(
        RoutePoster.accept('http://192.168.1.10:8096/Items/1/Images/Primary'),
        isNotNull,
      );
    });
  });

  group('a poster a route may not fetch', () {
    test('a host on the network nobody configured', () {
      RoutePoster.update(['http://192.168.1.10:8096']);

      expect(RoutePoster.accept('http://192.168.1.1/admin'), isNull);
      expect(RoutePoster.accept('https://192.168.1.1/admin'), isNull);
      expect(RoutePoster.accept('http://192.168.1.10:9000/x'), isNull);
      expect(RoutePoster.accept('https://router.local/x'), isNull);
      expect(RoutePoster.accept('https://nas/x'), isNull);
      expect(RoutePoster.accept('https://127.0.0.1:8080/x'), isNull);
      expect(RoutePoster.accept('https://[::1]/x'), isNull);
      expect(RoutePoster.accept('https://169.254.169.254/latest'), isNull);
      expect(RoutePoster.accept('https://nas.tail1234.ts.net/x'), isNull);
    });

    test('cleartext off the connections, credentials, other schemes', () {
      expect(
        RoutePoster.accept('http://image.tmdb.org/t/p/w342/a.jpg'),
        isNull,
      );
      expect(RoutePoster.accept('https://u:p@image.tmdb.org/a.jpg'), isNull);
      expect(RoutePoster.accept('file:///etc/hosts'), isNull);
      expect(RoutePoster.accept(''), isNull);
      expect(RoutePoster.accept(null), isNull);
    });
  });
}
