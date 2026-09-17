import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/services/presentation/widgets/instance_lens_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The band every service screen lives under: back chevron, the service's
/// identity (accent dot + name), and one trailing action.
///
/// The dot + title used to be a button opening a dropdown picker of all
/// seventeen services — the dashboard's own switcher. The Portal made it a
/// second, worse copy of the same instrument (drag the nav bar up from
/// anywhere, land on the real matrix), so the picker is gone and the title
/// went back to being what it looks like: the name of the room you are in.
/// Screen-reader users switch through the accessible path that always
/// existed — Services tab → matrix — since the Portal's drag is gesture-only.
class ServiceHomeScreen extends StatelessWidget {
  final ServiceKey service;
  final Widget child;
  final Widget? trailingAction;

  /// Whether to draw the band at all.
  ///
  /// The band is drawn above every branch navigator, so unlike the tab bar —
  /// which a pushed page simply covers — it cannot be hidden by the page that
  /// wants it gone, and has to be told. A pushed detail brings its own back
  /// control, floated top left, and two chevrons in one corner is what this
  /// answers.
  ///
  /// Defaults to true so the fourteen screens that host this band directly,
  /// with no tabs under them, are untouched.
  final bool showAppBar;

  const ServiceHomeScreen({
    super.key,
    required this.service,
    required this.child,
    this.trailingAction,
    this.showAppBar = true,
  });

  /// The room the band occupies measured from the very top of the screen —
  /// the top inset included.
  ///
  /// **The band is the one that consumes the inset.** It is `Positioned(top: 0)`
  /// under a `SafeArea`, so on a phone with a notch or a cutout it is a status
  /// bar taller than [kToolbarHeight]. Anything floated underneath it — the
  /// service tab bar — has to start at this, not at [kToolbarHeight], or it is
  /// laid out an inset too high and the band is drawn straight over it. The
  /// default test surface has no inset, which is exactly why that overlap can
  /// be invisible for as long as nobody pumps one.
  static double bandHeightOf(BuildContext context) =>
      kToolbarHeight + MediaQuery.paddingOf(context).top;

  @override
  Widget build(BuildContext context) {
    if (!showAppBar) return child;

    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          // Glass band instead of an opaque surface strip, so the hosted
          // screen's ambient gradient reads continuously behind the app bar
          // and scrolling content frosts underneath.
          child: GlassSurface(
            child: SafeArea(
              bottom: false,
              child: _ServiceDashboardAppBar(
                service: service,
                trailingAction: trailingAction,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceDashboardAppBar extends ConsumerWidget {
  final ServiceKey service;
  final Widget? trailingAction;

  const _ServiceDashboardAppBar({required this.service, this.trailingAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).appBarTheme.titleTextStyle;

    return SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.chevron_left_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: () => RouteUtils.popOrGo(
                context,
                ServiceRoutes.forService(service),
              ),
              tooltip: 'Back to Dashboard',
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: service.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            // Flexible, and the badge beside it is not: when the bar runs
            // out of room the *service name* is what gives way. Which service
            // you are in you already know — you navigated here. Which
            // connection you are reading is the part that has to stay legible,
            // and it is the shorter string anyway.
            //
            // Load-bearing beyond the badge: this Text had no constraint and no
            // overflow at all, and `clampedScalerOf` is opt-in per call site
            // rather than global. "Nginx Proxy Manager" at titleLarge/w800 and
            // an accessibility text scale overflowed the Row before any of this
            // existed.
            Flexible(
              child: Text(
                service.title,
                key: ValueKey('service-home-title-${service.routeParam}'),
                style: titleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
            InstanceLensBadge(service: service),
            const Spacer(),
            if (trailingAction != null)
              trailingAction!
            else
              IconButton(
                icon: Icon(Icons.monitor_heart_outlined, color: service.accent),
                onPressed: () => context.go('/activity'),
                tooltip: 'Activity',
              ),
          ],
        ),
      ),
    );
  }
}
