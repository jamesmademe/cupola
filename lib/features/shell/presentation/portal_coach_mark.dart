/// The Portal's coach mark: a pill above the nav bar, shown when the user has
/// made [PortalHintsState.coachJourneyThreshold] manual switches without ever
/// opening the Portal — the moment of demonstrated need, not first launch.
///
/// Its × is the Settings → Hints → Portal switch (which turns it back on);
/// opening the Portal resets the need-counter and the pill retires by itself.
/// When it appears, the bar plays one demo bounce so the words and the physics
/// arrive together.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/shell/domain/portal_hints.dart';
import 'package:cupola/features/shell/presentation/service_portal.dart';

class PortalCoachMark extends ConsumerStatefulWidget {
  const PortalCoachMark({super.key, required this.controller});

  final ServicePortalController controller;

  @override
  ConsumerState<PortalCoachMark> createState() => _PortalCoachMarkState();
}

class _PortalCoachMarkState extends ConsumerState<PortalCoachMark> {
  bool _wasVisible = false;

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(
      portalHintsProvider.select((s) => s.coachVisible),
    );
    if (visible && !_wasVisible) {
      // The invitation arrives with the words: one bounce, not a loop.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.playDemoBounce();
      });
    }
    _wasVisible = visible;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    // Just above the bar. Inside a body with `extendBody: true` the Scaffold
    // hands down a MediaQuery whose padding.bottom ALREADY includes the whole
    // bottomNavigationBar (bar + safe area): that figure IS the bar's top
    // edge — do not add the bar's own metrics on top of it.
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.sm,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedBuilder(
            // The coach does not talk over the Portal: as soon as t rises, it goes.
            animation: widget.controller.portal,
            builder: (context, child) => Opacity(
              opacity: (1 - widget.controller.portal.value * 3).clamp(0.0, 1.0),
              child: child,
            ),
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 0.35),
              duration: AppAnimation.durationSm,
              curve: AppAnimation.emphasizedCurve,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: AppAnimation.durationSm,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.only(left: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: AppRadius.borderRadiusLg,
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : colorScheme.outline,
                      ),
                      boxShadow: AppElevation.level2(colorScheme),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Swipe up to open the Portal',
                          style: theme.textTheme.labelLarge?.weight(
                            FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            // The same switch as Settings → Hints → Portal.
                            ref
                                .read(portalHintsProvider.notifier)
                                .setEnabled(false);
                          },
                          tooltip: 'Turn this hint off',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
