import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// The overline above a group of settings rows.
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      header: true,
      // The un-uppercased title: '.toUpperCase()' is typography, and VoiceOver
      // spells out all-caps tokens it does not recognise.
      label: title,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Text(
          title.toUpperCase(),
          style: AppTheme.eyebrow(colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
