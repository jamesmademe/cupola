import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/outside/domain/outside_link.dart';

void main() {
  test('a place goes out and comes back whole, its query too', () {
    const route = '/activity/download?i=qb&k=abc%20d';
    final link = OutsideLink.to(route);
    expect(link.scheme, 'cupola');
    expect(link.host, 'open');
    expect(OutsideLink.routeOf(link), route);
    expect(OutsideLink.routeOf(Uri.parse(link.toString())), route);
  });

  test('the path a router leaves of it reads the same', () {
    final bare = Uri(path: '/open', queryParameters: {'to': '/activity'});
    expect(OutsideLink.isOpenUri(bare), isTrue);
    expect(OutsideLink.routeOf(bare), '/activity');
  });

  test('only a place of the app opens: never an address or a scheme', () {
    for (final to in ['//evil.example', 'https://evil.example', 'activity']) {
      final link = OutsideLink.to(to);
      expect(OutsideLink.isOpenUri(link), isTrue, reason: to);
      expect(OutsideLink.routeOf(link), isNull, reason: to);
    }
    expect(OutsideLink.routeOf(Uri.parse('cupola://open')), isNull);
  });

  test('other links are not a widget\'s', () {
    expect(OutsideLink.isOpenUri(Uri.parse('cupola://pair?k=1')), isFalse);
    expect(OutsideLink.isOpenUri(Uri.parse('/open')), isFalse);
    expect(OutsideLink.isOpenUri(Uri.parse('/activity')), isFalse);
  });
}
