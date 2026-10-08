import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/home/domain/home_layout.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// The Home's layout for the person the shell is drawn for, kept on the
/// device.
///
/// Each person has their own (`HomeLayout.keyFor`): an operator who becomes a
/// requester on this phone finds her Home as she left it, and theirs is still
/// there if the stack comes back. Read from the preferences every time the
/// person changes; written on every change, like "Hide what I have".
final homeLayoutProvider = NotifierProvider<HomeLayoutNotifier, HomeLayout>(
  HomeLayoutNotifier.new,
);

class HomeLayoutNotifier extends Notifier<HomeLayout> {
  @override
  HomeLayout build() {
    final audience = ref.watch(shellAudienceProvider);
    // Guarded like the catalogue's switch: a test or a screen built without
    // the preferences still draws, with the default layout.
    try {
      final stored = ref
          .watch(sharedPreferencesProvider)
          .getString(HomeLayout.keyFor(audience));
      return HomeLayout.read(stored, audience);
    } catch (_) {
      return HomeLayout.defaultFor(audience);
    }
  }

  /// [module] one place up (`by: -1`) or down (`by: 1`).
  void move(HomeModule module, int by) => _save(state.moved(module, by));

  /// The drag of a reorderable list, in its own indices over the ordered
  /// modules.
  void reorder(int from, int to) => _save(state.reordered(from, to));

  void setOn(HomeModule module, {required bool on}) =>
      _save(state.switched(module, on: on));

  /// Back to the registry's layout. The stored value goes too, so a module
  /// added later starts as the registry starts it.
  void reset() {
    state = HomeLayout.defaultFor(state.audience);
    try {
      ref
          .read(sharedPreferencesProvider)
          .remove(HomeLayout.keyFor(state.audience));
    } catch (_) {
      // Nothing to persist to.
    }
  }

  void _save(HomeLayout next) {
    if (identical(next, state)) return;
    state = next;
    try {
      ref
          .read(sharedPreferencesProvider)
          .setString(HomeLayout.keyFor(next.audience), next.toJson());
    } catch (_) {
      // Kept for this launch only: nothing to persist to.
    }
  }
}
