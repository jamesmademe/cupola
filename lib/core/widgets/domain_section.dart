import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// A small, uppercase section label used to head a group of services that
/// belong to the same [ServiceDomain]. Shared by the Home dashboard, Settings
/// and onboarding so the domain grouping reads identically everywhere.
class DomainSectionHeader extends StatelessWidget {
  const DomainSectionHeader({
    super.key,
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
  });

  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      header: true,
      // The un-uppercased label: `.toUpperCase()` is typography, and VoiceOver
      // spells out all-caps tokens it does not recognise. The eye gets the caps,
      // the ear gets the word.
      label: label,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  label.toUpperCase(),
                  // One kicker per domain group, introducing the region below
                  // it — the case `AppTheme.eyebrow` exists for, and the only
                  // place tracking is authored rather than derived.
                  style: AppTheme.eyebrow(theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            // Left audible: callers use it for a live count, which is worth its
            // own node.
            ?trailing,
          ],
        ),
      ),
    );
  }
}
