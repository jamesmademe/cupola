import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';

/// The tab Settings was opened from, so its page can go back to it.
///
/// Settings has no place in the phone's bar: it opens from Stack's gear or
/// from the requester's account button, and its page is the root of a branch
/// of its own. A root has nothing to pop, so without this the page would have
/// no way back but the bar, and Android's back would leave the app from it.
/// Null when Settings was not opened from another tab (a deep link, the
/// desktop rail's own item, where the rail is the way back).
final settingsReturnProvider = NotifierProvider<SettingsReturn, NavTab?>(
  SettingsReturn.new,
);

class SettingsReturn extends Notifier<NavTab?> {
  @override
  NavTab? build() => null;

  // ignore: use_setters_to_change_properties
  void set(NavTab? tab) => state = tab;
}

/// Opens Settings from wherever [context] is: at its root, remembering the
/// tab it was opened from, or at [to] inside it (a service's setup form).
///
/// A form is pushed over the page that asked for it, so its back and its Save
/// land on that page in one step. Going to it left the person at the root of
/// Settings after the save, one more back away from where they started, and
/// lost the way back altogether wherever the caller forgot this function.
void openSettings(
  BuildContext context,
  WidgetRef ref, {
  String to = ServiceRoutes.settings,
}) {
  if (to != ServiceRoutes.settings) {
    context.push(to);
    return;
  }
  final index = StatefulNavigationShell.maybeOf(context)?.currentIndex;
  final from = index == null ? null : NavTab.values[index];
  ref
      .read(settingsReturnProvider.notifier)
      .set(from == NavTab.settings ? null : from);
  context.go(to);
}
