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

  const ServiceHomeScreen({
    super.key,
    required this.service,
    required this.child,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
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
              onPressed: () =>
                  RouteUtils.popOrGo(context, ServiceRoutes.dashboard),
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
