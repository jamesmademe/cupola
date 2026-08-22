import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
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
class ServiceDashboardScreen extends StatelessWidget {
  final ServiceKey service;
  final Widget child;
  final Widget? trailingAction;

  const ServiceDashboardScreen({
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

class _ServiceDashboardAppBar extends StatelessWidget {
  final ServiceKey service;
  final Widget? trailingAction;

  const _ServiceDashboardAppBar({required this.service, this.trailingAction});

  @override
  Widget build(BuildContext context) {
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
              onPressed: () => RouteUtils.popOrGo(context, '/services'),
              tooltip: 'Back to Services',
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
            Text(
              service.title,
              key: ValueKey('service-dashboard-title-${service.routeParam}'),
              style: titleStyle,
            ),
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
