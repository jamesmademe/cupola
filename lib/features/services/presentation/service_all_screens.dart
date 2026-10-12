import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/activity/presentation/widgets/requests_board.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';

/// Seerr's Requests tab: the household's requests on the Seerr the room is
/// on, the same list as Activity's Requests view (`RequestsBoard`), those
/// that wait for you first.
class ServiceAllRequestsScreen extends ConsumerWidget {
  /// Whether to draw this screen's own app bar.
  ///
  /// False inside Seerr's tab shell, where `ServiceHomeScreen` draws the
  /// service band and `ServiceTabScaffold` the tab bar above it: a third bar of
  /// its own would put two titles and two back chevrons in one corner.
  final bool showAppBar;

  /// Room those two glass bands take above this page, since they float over it
  /// rather than pushing it down.
  final double topPadding;

  const ServiceAllRequestsScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: showAppBar
          ? const _ServiceListAppBar(
              title: 'All requests',
              backRoute: ServiceRoutes.seerr,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(requestsProvider);
          ref.invalidate(requestsForProvider);
          try {
            await ref.read(requestsProvider.future);
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // The host's bands float over this list rather than pushing it down,
          // so the first row has to clear them itself. The top inset is part
          // of that room and has to be added here: hosted, there is no app bar
          // for the `Scaffold` to strip the padding for, and the band above
          // consumes it. Standalone this page draws its own app bar, which owns
          // the inset.
          padding: EdgeInsets.only(
            top:
                topPadding +
                (topPadding > 0 ? MediaQuery.paddingOf(context).top : 0),
            bottom:
                AppSpacing.lg +
                FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: const [RequestsBoard(only: '')],
        ),
      ),
    );
  }
}

class _ServiceListAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final String backRoute;

  const _ServiceListAppBar({required this.title, required this.backRoute});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return GlassAppBar(
      leading: IconButton(
        icon: const Icon(Icons.chevron_left_rounded),
        onPressed: () => RouteUtils.popOrGo(context, backRoute),
        tooltip: 'Back',
      ),
      title: Text(title),
    );
  }
}
