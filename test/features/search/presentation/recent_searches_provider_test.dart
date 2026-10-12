import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/search/presentation/recent_searches_provider.dart';

void main() {
  late ProviderContainer container;
  late RecentSearchesNotifier recents;

  setUp(() {
    container = ProviderContainer();
    recents = container.read(recentSearchesProvider.notifier);
  });
  tearDown(() => container.dispose());

  List<String> read() => container.read(recentSearchesProvider);

  test('one search typed letter by letter is one recent', () {
    recents
      ..add('Mat')
      ..add('Matri')
      ..add('Matrix');

    expect(read(), ['Matrix']);
  });

  test('shortening the latest search replaces it too', () {
    recents
      ..add('Dune')
      ..add('Dune Part Two')
      ..add('Dune Part');

    expect(read(), ['Dune Part']);
  });

  test('a different search keeps the ones before it', () {
    recents
      ..add('Matrix')
      ..add('Dune')
      ..add('matrix');

    expect(read(), ['matrix', 'Dune']);
  });

  test('a single character is not recorded', () {
    recents.add('M');

    expect(read(), isEmpty);
  });
}
