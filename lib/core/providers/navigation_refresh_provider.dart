import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/features/settings/domain/nav_tab.dart';

/// Enum for navigation sections.
///
/// Each counter is incremented when a bottom navigation tab is reselected.
enum NavigationSection { home, discover, activity, stack, requests }

/// Provider to trigger refresh for each navigation section.
/// Incrementing the counter signals that the section should refresh its data.
final navigationRefreshProvider = StateProvider.family<int, NavigationSection>(
  (ref, section) => 0,
);

/// Helper extension to trigger a refresh for a section
extension NavigationRefreshExtension on WidgetRef {
  /// Triggers a refresh for the given navigation section by incrementing its counter.
  void triggerNavigationRefresh(NavigationSection section) {
    read(navigationRefreshProvider(section).notifier).state++;
  }
}

/// The section a re-tap of [NavTab] refreshes. Settings has none: its
/// refresh is a command of its own ("Test all").
extension NavTabRefreshSection on NavTab {
  NavigationSection? get refreshSection => switch (this) {
    NavTab.home => NavigationSection.home,
    NavTab.discover => NavigationSection.discover,
    NavTab.activity => NavigationSection.activity,
    NavTab.stack => NavigationSection.stack,
    NavTab.requests => NavigationSection.requests,
    NavTab.settings => null,
  };
}
