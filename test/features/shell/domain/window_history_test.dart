import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/shell/domain/window_history.dart';

/// Back and forward through where the window has been, as a browser walks it.
void main() {
  late ProviderContainer container;
  WindowHistoryNotifier history() =>
      container.read(windowHistoryProvider.notifier);
  WindowHistory state() => container.read(windowHistoryProvider);

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('a first visit has nowhere to go either way', () {
    history().visit('/home');
    expect(state().canGoBack, isFalse);
    expect(state().canGoForward, isFalse);
    expect(history().back(), isNull);
    expect(history().forward(), isNull);
  });

  test('back and forward walk the visits, and arriving is not a visit', () {
    for (final place in ['/home', '/discover', '/activity?tab=history']) {
      history().visit(place);
    }
    expect(history().back(), '/discover');
    history().visit('/discover');
    expect(history().back(), '/home');
    history().visit('/home');
    expect(state().canGoBack, isFalse);
    expect(history().forward(), '/discover');
    history().visit('/discover');
    expect(history().forward(), '/activity?tab=history');
    history().visit('/activity?tab=history');
    expect(state().entries, ['/home', '/discover', '/activity?tab=history']);
  });

  test('a visit from the middle drops what lay ahead; the same place twice '
      'is one visit', () {
    for (final place in ['/home', '/discover', '/activity']) {
      history().visit(place);
    }
    history().back();
    history().visit('/discover');
    history().visit('/stack');
    history().visit('/stack');
    expect(state().entries, ['/home', '/discover', '/stack']);
    expect(state().canGoForward, isFalse);
  });

  test('it keeps a session\'s worth and no more', () {
    for (var i = 0; i < WindowHistory.maxEntries + 10; i++) {
      history().visit('/p$i');
    }
    expect(state().entries, hasLength(WindowHistory.maxEntries));
    expect(state().entries.first, '/p10');
    expect(state().index, WindowHistory.maxEntries - 1);
  });
}
