import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';

/// Claims Android's back for Settings opened from a tab.
///
/// Opened from a tab, Settings is the root of a branch whose page takes the
/// back to go to that tab (`SettingsHomeScreen`). With predictive back the
/// system hands a back to the app only when the framework has claimed it, and
/// no navigator claims one for a root: without this, a back on Settings left
/// the app. It sits above every navigator, in the app's `builder`, because
/// each of them says "nothing to pop" on its way up, the router's own last.
class SettingsBackClaim extends ConsumerWidget {
  const SettingsBackClaim({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      NotificationListener<NavigationNotification>(
        onNotification: (notification) {
          if (notification.canHandlePop || !_claims(ref)) return false;
          const NavigationNotification(canHandlePop: true).dispatch(context);
          return true;
        },
        child: child,
      );

  /// Settings at its root, with a tab to go back to. A page pushed on it is
  /// the navigators' to claim.
  static bool _claims(WidgetRef ref) =>
      ref.read(settingsReturnProvider) != null &&
      ref.read(routerProvider).state.uri.path == ServiceRoutes.settings;
}
