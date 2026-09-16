import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

/// Enum for navigation sections.
///
/// Each counter is incremented when a bottom navigation tab is reselected.
enum NavigationSection { dashboard, activity, search }

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
