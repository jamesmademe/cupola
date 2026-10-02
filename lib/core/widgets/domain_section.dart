import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// A small, sentence-case section label used to head a group of services that
/// belong to the same [ServiceDomain]. Today its one caller is the Connections
/// list in Settings; it stays in core so any other list grouped by domain reads
/// the same way.
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
      // The label as written, for the eye and the ear alike.
      label: label,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  label,
                  // One label per domain group, introducing the region below
                  // it, in the micro role and sentence case: there is no
                  // uppercase voice.
                  style: AppTheme.chrome(
                    context,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
