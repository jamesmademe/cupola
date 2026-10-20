import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';

/// Where this window has been, and where in that it stands: what the
/// toolbar's back and forward arrows walk.
///
/// A browser's history, not the navigator's stack. The stack only knows the
/// pages pushed inside one section, so a back that only popped it could not
/// take you from Activity back to the title you came from on Discover, which
/// is the trip a back arrow promises on a desktop.
@immutable
class WindowHistory {
  const WindowHistory({required this.entries, required this.index});

  static const empty = WindowHistory(entries: [], index: -1);

  /// The locations, oldest first, each with its query.
  final List<String> entries;

  /// The one the window is on, or -1 before the first visit.
  final int index;

  /// How far back it keeps: a session's worth, not a record.
  static const int maxEntries = 50;

  bool get canGoBack => index > 0;
  bool get canGoForward => index >= 0 && index < entries.length - 1;
}

final windowHistoryProvider =
    NotifierProvider<WindowHistoryNotifier, WindowHistory>(
      WindowHistoryNotifier.new,
    );

class WindowHistoryNotifier extends Notifier<WindowHistory> {
  /// Where a back or a forward is taking the window: its arrival is a step,
  /// not a new visit, and must not cut off what lies ahead.
  String? _arriving;

  @override
  WindowHistory build() => WindowHistory.empty;

  /// The window arrived at [location].
  ///
  /// A step taken with the arrows only moves the mark. Any other arrival is a
  /// visit: it drops what lay ahead, as a browser does, and the same place
  /// twice in a row is one visit.
  void visit(String location) {
    final arriving = _arriving;
    _arriving = null;
    if (arriving == location) return;
    final current = state;
    if (current.index >= 0 && current.entries[current.index] == location) {
      return;
    }
    var entries = [...current.entries.take(current.index + 1), location];
    if (entries.length > WindowHistory.maxEntries) {
      entries = entries.sublist(entries.length - WindowHistory.maxEntries);
    }
    state = WindowHistory(
      entries: List.unmodifiable(entries),
      index: entries.length - 1,
    );
  }

  /// One step back: where to go, or null with nowhere to go.
  String? back() => _step(-1);

  /// One step forward: where to go, or null with nowhere to go.
  String? forward() => _step(1);

  String? _step(int delta) {
    final current = state;
    final next = current.index + delta;
    if (current.index < 0 || next < 0 || next >= current.entries.length) {
      return null;
    }
    final location = current.entries[next];
    _arriving = location;
    state = WindowHistory(entries: current.entries, index: next);
    return location;
  }
}

/// Whether the person folded the sidebar to its rail of glyphs, in a window
/// wide enough to hold it whole. Remembered, as the inspector's width is: it is
/// how somebody arranged their workspace, not a place they went.
final sidebarFoldedProvider = NotifierProvider<SidebarFolded, bool>(
  SidebarFolded.new,
);

class SidebarFolded extends Notifier<bool> {
  static const _key = 'sidebar_folded';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  void toggle() {
    state = !state;
    ref.read(sharedPreferencesProvider).setBool(_key, state);
  }
}
