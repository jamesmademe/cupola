import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/shell/domain/portal_hints.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';

/// Settings → Hints: one switch per feature that teaches itself.
///
/// One row today — the Portal — because it is the only gesture the app has to
/// introduce. A row is a *feature*, not a mechanism: the Portal's demo bounce
/// and coach mark are two beats of one lesson and answer to one switch. When
/// another feature earns hints, it joins as its own row.
class SettingsHintsScreen extends ConsumerWidget {
  const SettingsHintsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(portalHintsProvider.select((s) => s.enabled));
    final theme = Theme.of(context);

    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('Hints')),
      body: SettingsMasterDetail(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Text(
                'Small nudges that introduce a gesture, then get out of the way. '
                'The × on a tip turns its switch off here.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SettingsGroupCard(
              children: [
                _HintRow(
                  icon: Icons.swipe_up_rounded,
                  title: 'Portal',
                  description:
                      'The bar lifts once to hint at the swipe, and a tip '
                      'appears if you keep switching services the long way. '
                      'Turn back on to see both again.',
                  enabled: enabled,
                  onChanged: (value) =>
                      ref.read(portalHintsProvider.notifier).setEnabled(value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: colors.primary),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}
